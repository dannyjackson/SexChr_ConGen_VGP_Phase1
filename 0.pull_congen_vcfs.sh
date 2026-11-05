#!/bin/bash
#SBATCH --job-name=pull_congen_vcfs
#SBATCH --partition=norm
#SBATCH --cpus-per-task=2
#SBATCH --mem=4g
#SBATCH --time=12:00:00
#SBATCH --output=pull_congen_vcfs.%A_%a.out
#SBATCH --error=pull_congen_vcfs.%A_%a.err

# Pull the VGP ConGen Phase 1 variant-calling outputs from GenomeArk (public S3)
# into the Wilson Lab data directory on Biowulf, one file per array task.
#
# Step 1 - build the file list (no SLURM needed; run on helix or a login node):
#   bash ${SCRIPTDIR}/0.pull_congen_vcfs.sh list
#
# Step 2 - submit one array task per file (%20 caps concurrent downloads at 20):
#   N=$(wc -l < ${DATADIR}/vcfs/s3_filelist.txt)
#   sbatch --array=1-${N}%20 ${SCRIPTDIR}/0.pull_congen_vcfs.sh
#
# Each task skips its file if it already exists with the correct size, so the
# array can be resubmitted to pick up any failures.

set -euo pipefail

PROJDIR=/data/Wilson_Lab/projects/ConGen_VGP_Phase1
DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
GITDIR=${PROJDIR}/scripts/
SCRIPTDIR=${PROJDIR}/scripts/SexChr_ConGen_VGP_Phase1

OUTDIR=${DATADIR}/vcfs
FILELIST=${OUTDIR}/s3_filelist.txt

BUCKET=s3://genomeark
PREFIX=downstream_analyses/conservation_genomics/variant_calling/

# Biowulf provides the AWS CLI as a module
module load aws 2>/dev/null || module load awscli 2>/dev/null || {
    echo "ERROR: could not load an AWS CLI module (tried 'aws' and 'awscli')." >&2
    exit 1
}

mkdir -p ${OUTDIR}

#---------------------------------------------------------------------------
# Mode 1: build the file list
#---------------------------------------------------------------------------
if [[ "${1:-}" == "list" ]]; then
    echo "Listing ${BUCKET}/${PREFIX}"

    # Full listing (date, time, size, key) kept for reference
    aws s3 ls --no-sign-request --recursive --human-readable --summarize \
        ${BUCKET}/${PREFIX} > ${OUTDIR}/s3_listing.txt

    # Two tab-separated columns: size in bytes, key relative to ${PREFIX}
    aws s3 ls --no-sign-request --recursive ${BUCKET}/${PREFIX} \
        | awk -v prefix="${PREFIX}" '
            $3 > 0 {
                size = $3
                key  = $0
                sub(/^ *[^ ]+ +[^ ]+ +[^ ]+ +/, "", key)   # strip date, time, size
                sub("^" prefix, "", key)
                print size "\t" key
            }' > ${FILELIST}

    N=$(wc -l < ${FILELIST})
    echo "Wrote ${N} files to ${FILELIST}"
    echo
    echo "Submit with:"
    echo "  sbatch --array=1-${N}%20 ${SCRIPTDIR}/0.pull_congen_vcfs.sh"
    exit 0
fi

#---------------------------------------------------------------------------
# Mode 2: array task - download one file
#---------------------------------------------------------------------------
if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
    echo "ERROR: run with 'list' first, then submit as a SLURM array (see header)." >&2
    exit 1
fi

if [[ ! -s ${FILELIST} ]]; then
    echo "ERROR: ${FILELIST} not found. Run 'bash 0.pull_congen_vcfs.sh list' first." >&2
    exit 1
fi

LINE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" ${FILELIST})
if [[ -z "${LINE}" ]]; then
    echo "ERROR: no entry at line ${SLURM_ARRAY_TASK_ID} of ${FILELIST}" >&2
    exit 1
fi

SIZE=$(cut -f1 <<< "${LINE}")
KEY=$(cut -f2- <<< "${LINE}")
SRC=${BUCKET}/${PREFIX}${KEY}
DEST=${OUTDIR}/${KEY}

echo "Task:        ${SLURM_ARRAY_TASK_ID}"
echo "Source:      ${SRC}"
echo "Destination: ${DEST}"
echo "Size:        ${SIZE} bytes"
echo "Started:     $(date)"

# Skip if already complete
if [[ -f ${DEST} && $(stat -c %s ${DEST}) -eq ${SIZE} ]]; then
    echo "Already downloaded, skipping."
    exit 0
fi

mkdir -p $(dirname ${DEST})

aws s3 cp --no-sign-request --no-progress ${SRC} ${DEST}

# Verify size
if [[ $(stat -c %s ${DEST}) -ne ${SIZE} ]]; then
    echo "ERROR: size mismatch for ${DEST} (expected ${SIZE}, got $(stat -c %s ${DEST}))" >&2
    exit 1
fi

echo "Finished:    $(date)"
