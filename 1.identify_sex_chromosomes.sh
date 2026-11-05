#!/bin/bash

# Build a table of the sex chromosome(s) present in each reference genome used by
# the VGP ConGen Phase 1 variant calling, plus the sex of the sequenced individual.
#
# The per-genome directories on GenomeArk are named by NCBI assembly accession, so
# the accession list is derived from the manifest written by 0.pull_congen_vcfs.sh.
# Everything else comes from NCBI via the datasets CLI:
#   - genome report    -> species, tax_id, BioSample sex attribute
#   - taxonomy report  -> class, order
#   - sequence report  -> chromosome names; anything named X/Y/Z/W (optionally
#                         numbered, e.g. X1 X2) is reported as a sex chromosome
#
# Usage (needs internet, so run on helix, not a compute node):
#   bash ${SCRIPTDIR}/1.identify_sex_chromosomes.sh
#
# Output:
#   ${PROJDIR}/1.sex_chromosomes.tsv
#     class  order  species  accession  sex_chromosomes  sex_of_sample
#   sex_chromosomes is comma-separated, "none" if no X/Y/Z/W-named chromosome,
#   or "no_chromosomes" if the assembly has no chromosome-level sequences at all.

set -euo pipefail

PROJDIR=/data/Wilson_Lab/projects/ConGen_VGP_Phase1
DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
GITDIR=${PROJDIR}/scripts/
SCRIPTDIR=${PROJDIR}/scripts/SexChr_ConGen_VGP_Phase1

FILELIST=${DATADIR}/vcfs/s3_filelist.txt
OUTTABLE=${PROJDIR}/1.sex_chromosomes.tsv
TMPDIR=${PROJDIR}/tmp/ncbi_reports
mkdir -p ${TMPDIR}

module load ncbi-datasets 2>/dev/null || module load datasets 2>/dev/null || true
command -v datasets >/dev/null || { echo "ERROR: 'datasets' CLI not found. module load ncbi-datasets, or download it from https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/" >&2; exit 1; }
command -v jq       >/dev/null || { echo "ERROR: jq not found (module load jq)" >&2; exit 1; }

if [[ ! -s ${FILELIST} ]]; then
    echo "ERROR: ${FILELIST} not found. Run 'bash 0.pull_congen_vcfs.sh list' first." >&2
    exit 1
fi

# Silence the "New version of client available" notice datasets prints on every call
datasets() { command datasets "$@" 2> >(grep -v 'New version of client' >&2); }

# Top-level directory of each key = assembly accession
ACCESSIONS=$(cut -f2 ${FILELIST} | cut -d/ -f1 | grep -E '^GC[AF]_[0-9]+\.[0-9]+$' | sort -u)
echo "Found $(wc -w <<< "${ACCESSIONS}") accessions in ${FILELIST}"

printf 'class\torder\tspecies\taccession\tsex_chromosomes\tsex_of_sample\n' > ${OUTTABLE}

for ACC in ${ACCESSIONS}; do
    echo "--- ${ACC}"

    #-- genome report: species, tax_id, biosample sex ----------------------
    GENOME_JSON=${TMPDIR}/${ACC}.genome.json
    if [[ ! -s ${GENOME_JSON} ]]; then
        datasets summary genome accession ${ACC} --as-json-lines > ${GENOME_JSON}
    fi

    SPECIES=$(jq -r '.organism.organism_name // "NA"' ${GENOME_JSON})
    TAXID=$(jq -r '.organism.tax_id // empty' ${GENOME_JSON})
    SEX=$(jq -r '
        [ (.assembly_info.biosample.attributes // [])[]
          | select(.name | ascii_downcase == "sex") | .value ][0]
        // .assembly_info.biosample.sex
        // "NA"' ${GENOME_JSON} | tr '[:upper:]' '[:lower:]')

    #-- taxonomy report: class, order --------------------------------------
    CLASS=NA; ORDER=NA
    if [[ -n "${TAXID}" ]]; then
        TAX_JSON=${TMPDIR}/${ACC}.taxonomy.json
        if [[ ! -s ${TAX_JSON} ]]; then
            datasets summary taxonomy taxon ${TAXID} --as-json-lines > ${TAX_JSON}
        fi
        CLASS=$(jq -r '.taxonomy.classification.class.name // "NA"' ${TAX_JSON})
        ORDER=$(jq -r '.taxonomy.classification.order.name // "NA"' ${TAX_JSON})
    fi

    #-- sequence report: chromosome names ----------------------------------
    SEQ_JSON=${TMPDIR}/${ACC}.sequences.json
    if [[ ! -s ${SEQ_JSON} ]]; then
        datasets summary genome accession ${ACC} --report sequence --as-json-lines > ${SEQ_JSON}
    fi

    CHROMS=$(jq -r '
        select(.assigned_molecule_location_type == "Chromosome"
               and .role == "assembled-molecule")
        | .chr_name' ${SEQ_JSON} | sort -u)

    if [[ -z "${CHROMS}" ]]; then
        SEXCHR=no_chromosomes
    else
        SEXCHR=$(grep -Ei '^(chr)?[XYZW][0-9]*$' <<< "${CHROMS}" | sed -E 's/^chr//I' | sort -u | paste -sd, -)
        SEXCHR=${SEXCHR:-none}
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${CLASS}" "${ORDER}" "${SPECIES}" "${ACC}" "${SEXCHR}" "${SEX}" >> ${OUTTABLE}
done

echo
echo "Wrote ${OUTTABLE}"
column -t -s $'\t' ${OUTTABLE}
