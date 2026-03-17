#!/usr/bin/env python3
"""
CSV to FHIR Transformer for Pathology Gamma

Reads CSV files containing local pathology codes and mappings, and produces
FHIR CodeSystem and ConceptMap resources with appropriate security labels.

Usage:
    python3 csv-transform.py \
        --codes gamma-codes.csv \
        --mappings gamma-mappings.csv \
        --output-dir ./output \
        --security-label GAMMA \
        --codesystem-url http://pathology-gamma.example.com/CodeSystem/pathology-codes \
        --conceptmap-url http://pathology-gamma.example.com/ConceptMap/pathology-to-national \
        --target-valueset http://example.org/ValueSet/national-pathology-refset \
        --publisher "Pathology Gamma"

This script simulates a real-world pattern where terminology content is
maintained in a version-controlled CSV format (e.g., in a Git repository)
and transformed into FHIR resources for loading into Ontoserver.
"""

import argparse
import csv
import json
import os
import sys
from datetime import date


PERMISSIONS_SYSTEM = "http://ontoserver.csiro.au/CodeSystem/ontoserver-permissions"


def build_security_labels(label):
    """Build FHIR security labels for a community."""
    return [
        {"system": PERMISSIONS_SYSTEM, "code": f"{label}.read"},
        {"system": PERMISSIONS_SYSTEM, "code": f"{label}.write"},
    ]


def read_codes_csv(filepath):
    """Read the codes CSV file and return a list of concept dicts."""
    concepts = []
    with open(filepath, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            concept = {
                "code": row["code"].strip(),
                "display": row["display"].strip(),
            }
            if row.get("definition", "").strip():
                concept["definition"] = row["definition"].strip()
            concepts.append(concept)
    return concepts


def read_mappings_csv(filepath):
    """Read the mappings CSV file and return grouped mapping elements."""
    elements = []
    with open(filepath, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            target = {
                "code": row["target_code"].strip(),
                "display": row["target_display"].strip(),
                "equivalence": row["equivalence"].strip(),
            }
            if row.get("comment", "").strip():
                target["comment"] = row["comment"].strip()

            element = {
                "code": row["source_code"].strip(),
                "display": row.get("source_display", "").strip(),
                "target": [target],
            }
            elements.append(element)
    return elements


def build_codesystem(concepts, args):
    """Build a FHIR CodeSystem resource from CSV concepts."""
    return {
        "resourceType": "CodeSystem",
        "id": args.codesystem_id,
        "meta": {"security": build_security_labels(args.security_label)},
        "url": args.codesystem_url,
        "version": args.version,
        "name": args.codesystem_name,
        "title": f"{args.publisher} - Local Pathology Order Codes",
        "status": "draft",
        "experimental": False,
        "date": date.today().isoformat(),
        "publisher": args.publisher,
        "description": (
            f"Local pathology order codes for {args.publisher}. "
            "Generated from CSV source data maintained in version control."
        ),
        "content": "complete",
        "count": len(concepts),
        "concept": concepts,
    }


def build_conceptmap(elements, source_system, args):
    """Build a FHIR ConceptMap resource from CSV mappings."""
    # Group elements by target system
    groups = {}
    for elem in elements:
        target_system = args.target_system
        if not groups.get(target_system):
            groups[target_system] = []
        groups[target_system].append(elem)

    fhir_groups = []
    for target_sys, group_elements in groups.items():
        fhir_groups.append({
            "source": source_system,
            "target": target_sys,
            "element": group_elements,
        })

    return {
        "resourceType": "ConceptMap",
        "id": args.conceptmap_id,
        "meta": {"security": build_security_labels(args.security_label)},
        "url": args.conceptmap_url,
        "version": args.version,
        "name": args.conceptmap_name,
        "title": f"{args.publisher} - Local Codes to National Standard Mapping",
        "status": "draft",
        "experimental": False,
        "date": date.today().isoformat(),
        "publisher": args.publisher,
        "description": (
            f"Maps {args.publisher}'s local pathology order codes to the national "
            "pathology standard codes. "
            "Generated from CSV source data maintained in version control."
        ),
        "sourceUri": source_system,
        "targetUri": args.target_valueset,
        "group": fhir_groups,
    }


def write_json(resource, filepath):
    """Write a FHIR resource to a JSON file."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(resource, f, indent=2, ensure_ascii=False)
    print(f"  Written: {filepath}")


def main():
    parser = argparse.ArgumentParser(
        description="Transform CSV pathology data into FHIR CodeSystem and ConceptMap resources"
    )
    parser.add_argument("--codes", required=True, help="Path to codes CSV file")
    parser.add_argument("--mappings", required=True, help="Path to mappings CSV file")
    parser.add_argument("--output-dir", required=True, help="Output directory for FHIR JSON files")
    parser.add_argument("--security-label", required=True, help="Security label for the community (e.g., GAMMA)")
    parser.add_argument("--codesystem-url", required=True, help="Canonical URL for the CodeSystem")
    parser.add_argument("--codesystem-id", default=None, help="Resource ID for the CodeSystem")
    parser.add_argument("--codesystem-name", default=None, help="Name for the CodeSystem")
    parser.add_argument("--conceptmap-url", required=True, help="Canonical URL for the ConceptMap")
    parser.add_argument("--conceptmap-id", default=None, help="Resource ID for the ConceptMap")
    parser.add_argument("--conceptmap-name", default=None, help="Name for the ConceptMap")
    parser.add_argument("--target-valueset", required=True, help="Target ValueSet URI for the ConceptMap")
    parser.add_argument("--target-system", default="http://example.org/CodeSystem/national-pathology-codes",
                        help="Target CodeSystem URI for ConceptMap groups (default: national pathology codes)")
    parser.add_argument("--publisher", required=True, help="Publisher name")
    parser.add_argument("--version", default="1.0.0", help="Resource version (default: 1.0.0)")

    args = parser.parse_args()

    # Set defaults for optional fields
    if not args.codesystem_id:
        args.codesystem_id = f"{args.security_label.lower()}-pathology-codes"
    if not args.codesystem_name:
        args.codesystem_name = f"Pathology{args.security_label.capitalize()}PathologyCodes"
    if not args.conceptmap_id:
        args.conceptmap_id = f"{args.security_label.lower()}-pathology-to-national"
    if not args.conceptmap_name:
        args.conceptmap_name = f"Pathology{args.security_label.capitalize()}PathologyToNational"

    print(f"CSV to FHIR Transformer")
    print(f"  Security label: {args.security_label}")
    print(f"  Codes CSV:      {args.codes}")
    print(f"  Mappings CSV:   {args.mappings}")
    print()

    # Read CSV data
    concepts = read_codes_csv(args.codes)
    print(f"  Read {len(concepts)} concepts from codes CSV")

    elements = read_mappings_csv(args.mappings)
    print(f"  Read {len(elements)} mappings from mappings CSV")
    print()

    # Build FHIR resources
    codesystem = build_codesystem(concepts, args)
    conceptmap = build_conceptmap(elements, args.codesystem_url, args)

    # Write output
    print("Writing FHIR resources:")
    cs_path = os.path.join(args.output_dir, f"{args.codesystem_id}.json")
    cm_path = os.path.join(args.output_dir, f"{args.conceptmap_id}.json")

    write_json(codesystem, cs_path)
    write_json(conceptmap, cm_path)

    print()
    print("Transformation complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
