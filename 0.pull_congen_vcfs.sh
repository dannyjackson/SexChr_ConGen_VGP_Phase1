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
# Step 1 - build the full file list (no SLURM needed; run on helix or a login node):
#   bash ${SCRIPTDIR}/0.pull_congen_vcfs.sh list
#
# Step 2 - (optional) subset the list, keeping the two-column size<TAB>key format:
#   grep -v 'gvcf' ${DATADIR}/vcfs/s3_filelist.txt | grep 'raw.vcf' \
#       > ${DATADIR}/vcfs/s3_filelist.raw_vcfs.txt
#
# Step 3 - submit one array task per line of the chosen list (%20 caps concurrency):
#   LIST=${DATADIR}/vcfs/s3_filelist.raw_vcfs.txt
#   N=$(wc -l < ${LIST})
#   sbatch --array=1-${N}%20 ${SCRIPTDIR}/0.pull_congen_vcfs.sh ${LIST}
#
# If no list is given, the full s3_filelist.txt is used. Each task skips its file
# if it already exists with the correct size, so an array can be resubmitted to
# pick up failures.

set -euo pipefail

PROJDIR=/data/Wilson_Lab/projects/ConGen_VGP_Phase1
DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
GITDIR=${PROJDIR}/scripts/
SCRIPTDIR=${PROJDIR}/scripts/SexChr_ConGen_VGP_Phase1

OUTDIR=${DATADIR}/vcfs
FULLLIST=${OUTDIR}/s3_filelist.txt

BUCKET=s3://genomeark
PREFIX=downstream_analyses/conservation_genomics/variant_calling/

# Biowulf provides the AWS CLI as a module
module load aws 2>/dev/null || module load awscli 2>/dev/null || {
    echo "ERROR: could not load an AWS CLI module (tried 'aws' and 'awscli')." >&2
    exit 1
}

mkdir -p ${OUTDIR}

#---------------------------------------------------------------------------
# Mode 1: build the full file list (single pass over S3)
#---------------------------------------------------------------------------
if [[ "${1:-}" == "list" ]]; then
    echo "Listing ${BUCKET}/${PREFIX} (paged 1000 keys at a time; can take minutes)"

    # Raw listing kept for reference: date, time, size, key
    aws s3 ls --no-sign-request --recursive ${BUCKET}/${PREFIX} > ${OUTDIR}/s3_listing.txt

    # Two tab-separated columns: size in bytes, key relative to ${PREFIX}
    awk -v prefix="${PREFIX}" '
        $3 > 0 {
            size = $3
            key  = $0
            sub(/^ *[^ ]+ +[^ ]+ +[^ ]+ +/, "", key)   # strip date, time, size
            sub("^" prefix, "", key)
            print size "\t" key
        }' ${OUTDIR}/s3_listing.txt > ${FULLLIST}

    N=$(wc -l < ${FULLLIST})
    echo "Wrote ${N} files to ${FULLLIST}"
    echo
    echo "Submit the full list with:"
    echo "  sbatch --array=1-${N}%20 ${SCRIPTDIR}/0.pull_congen_vcfs.sh"
    echo "or subset it first (grep on ${FULLLIST}) and pass the subset as the argument."
    exit 0
fi

#---------------------------------------------------------------------------
# Mode 2: array task - download one file from the given (or full) list
#---------------------------------------------------------------------------
FILELIST=${1:-${FULLLIST}}

if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
    echo "ERROR: run with 'list' first, then submit as a SLURM array (see header)." >&2
    exit 1
fi

if [[ ! -s ${FILELIST} ]]; then
    echo "ERROR: ${FILELIST} not found or empty." >&2
    exit 1
fi

LINE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" ${FILELIST})
if [[ -z "${LINE}" ]]; then
    echo "ERROR: no entry at line ${SLURM_ARRAY_TASK_ID} of ${FILELIST}" >&2
    exit 1
fi

SIZE=$(cut -f1 <<< "${LINE}")
KEY=$(cut -f2- <<< "${LINE}")

if ! [[ "${SIZE}" =~ ^[0-9]+$ ]] || [[ -z "${KEY}" ]]; then
    echo "ERROR: line ${SLURM_ARRAY_TASK_ID} of ${FILELIST} is not size<TAB>key: '${LINE}'" >&2
    exit 1
fi

SRC=${BUCKET}/${PREFIX}${KEY}
DEST=${OUTDIR}/${KEY}

echo "Task:        ${SLURM_ARRAY_TASK_ID}"
echo "List:        ${FILELIST}"
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
