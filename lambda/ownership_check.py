"""Ownership attestation Lambda.

Runs on a schedule: discovers owner-tagged resources, classifies each as
ok / stale / orphaned against the registry, writes the status back as a tag, and
publishes a findings summary to SNS. Flag-only: tags and notifies; never stops,
deletes, or modifies a resource.

Owner resolution sits behind one seam (FlatFileIdentitySource); a future identity
source implements the same read-only resolve() contract.
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import os
from dataclasses import dataclass

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configuration (injected by Terraform; see ownership.tf).
OWNER_TAG_KEY = os.environ.get("OWNER_TAG_KEY", "owner")
STATUS_TAG_KEY = os.environ.get("STATUS_TAG_KEY", "ownership:status")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
# JSON env var (small registries; the 4KB env limit is the trigger to move to
# SSM/DynamoDB at scale).
OWNERS_REGISTRY = json.loads(os.environ.get("OWNERS_REGISTRY", "{}"))
RESOURCE_TYPE_FILTERS = json.loads(os.environ.get("RESOURCE_TYPE_FILTERS", "[]"))

STATUS_OK = "ok"
STATUS_STALE = "stale"
STATUS_ORPHANED = "orphaned"


@dataclass(frozen=True)
class OwnershipStatus:
    """The resolved standing of an owner: exists + is_current => the status."""

    exists: bool
    is_current: bool
    team: str | None
    detail: str

    @property
    def status(self) -> str:
        if not self.exists:
            return STATUS_ORPHANED
        if not self.is_current:
            return STATUS_STALE
        return STATUS_OK


class FlatFileIdentitySource:
    """Resolves an owner id against the flat-file registry.

    The single owner-resolution seam; a future identity source implements the
    same read-only resolve() contract.
    """

    def __init__(self, registry: dict[str, dict]) -> None:
        self._by_id = registry

    def resolve(self, owner_id: str, today: dt.date) -> OwnershipStatus:
        entry = self._by_id.get(owner_id)
        if entry is None:
            return OwnershipStatus(False, False, None, f"owner '{owner_id}' is not in the registry")

        attested_on = _parse_date(entry["attested_on"])
        valid_for_days = int(entry.get("valid_for_days", 0))
        expires_on = attested_on + dt.timedelta(days=valid_for_days)
        is_current = today <= expires_on
        detail = "attestation current" if is_current else f"attestation expired on {expires_on.isoformat()}"
        return OwnershipStatus(True, is_current, entry.get("team"), detail)


def _parse_date(value: object) -> dt.date:
    """Accept an ISO date or RFC3339 timestamp (yamldecode coerces dates)."""
    return dt.date.fromisoformat(str(value).split("T")[0])


def _discover(tagging) -> list[dict]:
    """Resources carrying the owner tag, with their ARN, owner, current status."""
    kwargs: dict = {"TagFilters": [{"Key": OWNER_TAG_KEY}]}
    if RESOURCE_TYPE_FILTERS:
        kwargs["ResourceTypeFilters"] = RESOURCE_TYPE_FILTERS

    resources = []
    for page in tagging.get_paginator("get_resources").paginate(**kwargs):
        for mapping in page["ResourceTagMappingList"]:
            tags = {t["Key"]: t["Value"] for t in mapping.get("Tags", [])}
            resources.append(
                {
                    "arn": mapping["ResourceARN"],
                    "owner": tags.get(OWNER_TAG_KEY, ""),
                    "current_status": tags.get(STATUS_TAG_KEY),
                }
            )
    return resources


def handler(event, context):  # noqa: ARG001 - Lambda signature
    today = dt.datetime.now(dt.timezone.utc).date()
    source = FlatFileIdentitySource(OWNERS_REGISTRY)
    tagging = boto3.client("resourcegroupstaggingapi")
    sns = boto3.client("sns")

    findings: dict[str, list] = {STATUS_OK: [], STATUS_STALE: [], STATUS_ORPHANED: []}
    retagged = 0

    for resource in _discover(tagging):
        result = source.resolve(resource["owner"], today)
        status = result.status
        findings[status].append(
            {"arn": resource["arn"], "owner": resource["owner"], "detail": result.detail}
        )

        # Idempotent: only write the status tag when it actually changed.
        if resource["current_status"] != status:
            try:
                tagging.tag_resources(
                    ResourceARNList=[resource["arn"]],
                    Tags={STATUS_TAG_KEY: status},
                )
                retagged += 1
            except Exception:  # noqa: BLE001 - log and continue; never fail the whole run
                logger.exception("failed to tag %s", resource["arn"])

        logger.info(
            json.dumps(
                {"arn": resource["arn"], "owner": resource["owner"], "status": status, "detail": result.detail}
            )
        )

    summary = {
        "evaluated": sum(len(v) for v in findings.values()),
        "ok": len(findings[STATUS_OK]),
        "stale": len(findings[STATUS_STALE]),
        "orphaned": len(findings[STATUS_ORPHANED]),
        "retagged": retagged,
    }
    logger.info(json.dumps({"summary": summary}))

    # Notify only when there is something to flag.
    flagged = findings[STATUS_STALE] + findings[STATUS_ORPHANED]
    if flagged:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[ownership] {len(flagged)} resource(s) need attention"[:100],
            Message=json.dumps(
                {
                    "summary": summary,
                    "stale": findings[STATUS_STALE],
                    "orphaned": findings[STATUS_ORPHANED],
                },
                indent=2,
            ),
        )

    return summary
