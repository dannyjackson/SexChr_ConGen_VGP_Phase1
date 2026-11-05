#!/bin/bash
#SBATCH --job-name=pull_congen_vcfs
#SBATCH --partition=norm
#SBATCH --cpus-per-task=4
#SBATCH --mem=8g
#SBATCH --time=24:00:00
#SBATCH --output=pull_congen_vcfs.%j.out
#SBATCH --error=pull_congen_vcfs.%j.err

# Pull the VGP ConGen Phase 1 variant-calling outputs from GenomeArk (public S3)
# into the Wilson Lab data directory on Biowulf.
#
# Usage:
#   sbatch pull_congen_vcfs.sh            # run as a batch job (recommended)
#   bash pull_congen_vcfs.sh              # or run interactively on helix
#   bash pull_congen_vcfs.sh --dryrun     # list what would be transferred, no download
#
# aws s3 sync is resumable: re-running only fetches missing/changed files.

set -euo pipefail

DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
OUTDIR=$DATADIR/vcfs

BUCKET=s3://genomeark
PREFIX=downstream_analyses/conservation_genomics/variant_calling/

DRYRUN=""
if [[ "${1:-}" == "--dryrun" ]]; then
    DRYRUN="--dryrun"
fi

# Biowulf provides the AWS CLI as a module
module load aws 2>/dev/null || module load awscli 2>/dev/null || {
    echo "ERROR: could not load an AWS CLI module (tried 'aws' and 'awscli')." >&2
    exit 1
}

mkdir -p "$OUTDIR"

echo "Source:      $BUCKET/$PREFIX"
echo "Destination: $OUTDIR"
echo "Started:     $(date)"
echo

# Show what is in the bucket prefix before transferring
aws s3 ls --no-sign-request --recursive --human-readable --summarize "$BUCKET/$PREFIX" \
    | tee "$OUTDIR/s3_listing.txt"
echo

# Mirror the prefix (including subdirectories) into $OUTDIR
aws s3 sync --no-sign-request --no-progress $DRYRUN \
    "$BUCKET/$PREFIX" "$OUTDIR/"

echo
echo "Finished:    $(date)"
echo "Files in $OUTDIR:"
find "$OUTDIR" -type f | wc -l
du -sh "$OUTDIR"
