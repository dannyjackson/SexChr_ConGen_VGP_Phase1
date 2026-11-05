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
#   ${PROJDIR}/1.sex_chromosomes.tsv   (one row per genome)
#     class  order  species  accession  sex_chromosomes  sex_of_sample  X  Y  Z  W  X1 ...
#     sex_chromosomes is comma-separated, "none" if no X/Y/Z/W-named chromosome,
#     or "no_chromosomes" if the assembly has no chromosome-level sequences at all.
#     Then one column per sex chromosome name seen anywhere in the dataset, holding
#     that chromosome's sequence accession (GenBank, or RefSeq if no GenBank) for
#     this genome, or "." if the genome has no chromosome of that name.
#
#   ${PROJDIR}/1.sex_chromosomes.long.tsv   (one row per sex chromosome)
#     accession  chr_name  genbank_accession  refseq_accession  length_bp
#     Use this one for filtering, e.g. all W/Y (sex-limited) sequences:
#       awk -F'\t' '$2 ~ /^[WY]/' 1.sex_chromosomes.long.tsv

set -euo pipefail

PROJDIR=/data/Wilson_Lab/projects/ConGen_VGP_Phase1
DATADIR=/data/Wilson_Lab/data/ConGen_VGP_Phase1
GITDIR=${PROJDIR}/scripts/
SCRIPTDIR=${PROJDIR}/scripts/SexChr_ConGen_VGP_Phase1

FILELIST=${DATADIR}/vcfs/s3_filelist.txt
OUTTABLE=${PROJDIR}/1.sex_chromosomes.tsv
LONGTABLE=${PROJDIR}/1.sex_chromosomes.long.tsv
TMPDIR=${PROJDIR}/tmp/ncbi_reports
mkdir -p ${TMPDIR}
SUMMARY=${TMPDIR}/summary.tsv   # per-genome rows before sex-chromosome columns are added

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

printf 'class\torder\tspecies\taccession\tsex_chromosomes\tsex_of_sample\n' > ${SUMMARY}
printf 'accession\tchr_name\tgenbank_accession\trefseq_accession\tlength_bp\n' > ${LONGTABLE}

for ACC in ${ACCESSIONS}; do
    echo "--- ${ACC}"

    #-- genome report: species, tax_id, biosample sex ----------------------
    GENOME_JSON=${TMPDIR}/${ACC}.genome.json
    if [[ ! -s ${GENOME_JSON} ]]; then
        datasets summary genome accession ${ACC} --as-json-lines > ${GENOME_JSON} \
            || { echo "WARNING: genome report failed for ${ACC}, skipping" >&2; rm -f ${GENOME_JSON}; continue; }
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
            datasets summary taxonomy taxon ${TAXID} --as-json-lines > ${TAX_JSON} \
                || { echo "WARNING: taxonomy report failed for ${ACC} (taxid ${TAXID})" >&2; rm -f ${TAX_JSON}; }
        fi
        if [[ -s ${TAX_JSON} ]]; then
            CLASS=$(jq -r '.taxonomy.classification.class.name // "NA"' ${TAX_JSON})
            ORDER=$(jq -r '.taxonomy.classification.order.name // "NA"' ${TAX_JSON})
        fi
    fi

    #-- sequence report: chromosome names ----------------------------------
    SEQ_JSON=${TMPDIR}/${ACC}.sequences.json
    if [[ ! -s ${SEQ_JSON} ]]; then
        datasets summary genome accession ${ACC} --report sequence --as-json-lines > ${SEQ_JSON} \
            || { echo "WARNING: sequence report failed for ${ACC}" >&2; rm -f ${SEQ_JSON}; }
    fi

    # All assembled chromosomes: chr_name, genbank, refseq, length (tab-separated)
    CHROMS=""
    if [[ -s ${SEQ_JSON} ]]; then
        CHROMS=$(jq -r '
            select(.assigned_molecule_location_type == "Chromosome"
                   and .role == "assembled-molecule")
            | [ (.chr_name | sub("^(?i)chr"; "")),
                (.genbank_accession // "NA"),
                (.refseq_accession  // "NA"),
                (.length            // "NA" | tostring) ]
            | @tsv' ${SEQ_JSON} | sort -u)
    fi

    if [[ -z "${CHROMS}" ]]; then
        SEXCHR=no_chromosomes
    else
        # grep exits 1 on no match, which would trip set -e; the || true keeps us going
        SEXROWS=$( { grep -Ei $'^[XYZW][0-9]*\t' <<< "${CHROMS}" || true; } )
        if [[ -n "${SEXROWS}" ]]; then
            SEXCHR=$(cut -f1 <<< "${SEXROWS}" | sort -u | paste -sd, -)
            awk -v acc="${ACC}" 'BEGIN{OFS="\t"} {print acc, $0}' <<< "${SEXROWS}" >> ${LONGTABLE}
        else
            SEXCHR=none
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${CLASS}" "${ORDER}" "${SPECIES}" "${ACC}" "${SEXCHR}" "${SEX}" >> ${SUMMARY}
done

#---------------------------------------------------------------------------
# Add one column per sex chromosome name seen in the dataset, holding the
# sequence accession (GenBank, else RefSeq) of that chromosome in each genome.
# Column order: X, X1, X2 ..., Y, Y1 ..., Z ..., W ...
#---------------------------------------------------------------------------
awk -F'\t' 'BEGIN{OFS="\t"}
    # First file: long table -> acc[genome, chr] = sequence accession
    FNR==NR {
        if (FNR==1) next
        seqacc = ($3 != "NA") ? $3 : $4
        acc[$1 SUBSEP $2] = seqacc
        if (!($2 in seen)) { seen[$2]=1; names[++n]=$2 }
        next
    }
    # Second file: summary table
    FNR==1 {
        # sort chromosome names: letter in XYZW order, then number
        split("X Y Z W", L, " ")
        for (i=1;i<=4;i++) rank[L[i]]=i
        for (i=1;i<=n;i++) {
            letter=substr(names[i],1,1); num=substr(names[i],2); if (num=="") num=0
            key[i]=sprintf("%d_%05d", rank[toupper(letter)], num)
        }
        for (i=1;i<=n;i++) for (j=i+1;j<=n;j++)
            if (key[j] < key[i]) { t=names[i];names[i]=names[j];names[j]=t; t=key[i];key[i]=key[j];key[j]=t }
        line=$0
        for (i=1;i<=n;i++) line=line OFS names[i]
        print line; next
    }
    {
        line=$0
        for (i=1;i<=n;i++) { k=$4 SUBSEP names[i]; line=line OFS ((k in acc) ? acc[k] : ".") }
        print line
    }' ${LONGTABLE} ${SUMMARY} > ${OUTTABLE}

echo
echo "Wrote ${OUTTABLE} and ${LONGTABLE}"
command -v column >/dev/null && column -t -s $'\t' ${OUTTABLE} || cat ${OUTTABLE}
