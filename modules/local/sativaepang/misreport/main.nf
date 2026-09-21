
process SATIVAEPANG_MISREPORT {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    // quay.io/biocontainers/python:3.11 has no build-hash-suffixed tag to pin to (unlike
    // real bioconda-recipe images); pin by digest instead so the underlying image can't
    // silently drift between runs.
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python@sha256:b322907f8e52b2055ccad4e46848d28a4a5631b403116cc80ddf61ec8601e05e' }"

    input:
    tuple val(meta), path(mis), path(taskdir)

    output:
    tuple val(meta), path("*.mislabels.tsv"), emit: mislabels
    tuple val(meta), path("*.summary.txt"),   emit: summary
    path "versions.yml",                      emit: versions, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def args   = task.ext.args   ?: ''
    """
    python3 - "${mis}" "${taskdir}/manifest.json" "${prefix}.mislabels.tsv" "${prefix}.summary.txt" ${args} << 'PYEOF'
import argparse
import json
import sys

parser = argparse.ArgumentParser()
parser.add_argument('mis_file')
parser.add_argument('manifest_file')
parser.add_argument('mislabels_tsv')
parser.add_argument('summary_txt')
parser.add_argument('--min-lwr', type=float, default=0.5,
                     help='Minimum confidence at the mismatching rank required to trust it enough to flag a mislabel.')
opts = parser.parse_args()

# sativa-epang's .mis format: ';'-prefixed header/comment lines, then one
# tab-separated data row per flagged sequence:
#   SeqID  MislabeledLevel  OriginalLabel  ProposedLabel  Confidence
#   OriginalTaxonomyPath  ProposedTaxonomyPath  PerRankConfidence
# MislabeledLevel is a rank NAME (e.g. "Phylum"), not a position, so the numeric
# mismatch_rank below is derived from the taxonomy paths themselves (first
# differing ';'-separated token) rather than trusting that name.
rows = []
with open(opts.mis_file) as fh:
    for line in fh:
        line = line.rstrip('\\n')
        if not line or line.startswith(';'):
            continue
        seq_name, _level, _original, _proposed, confidence, original_path, proposed_path, _per_rank = line.split('\\t')
        original_ranks = original_path.split(';')
        proposed_ranks = proposed_path.split(';')
        mismatch_rank = None
        for i, (o, p) in enumerate(zip(original_ranks, proposed_ranks)):
            if o != p:
                mismatch_rank = i + 1
                break
        if mismatch_rank is None and len(original_ranks) != len(proposed_ranks):
            # Paths agree over their shared prefix but differ in depth (one a
            # strict prefix of the other) -- sativa-epang still considers this
            # row mislabeled (it's in .mis at all), so the mismatch has to be
            # the first rank beyond that shared prefix, not "no mismatch".
            mismatch_rank = min(len(original_ranks), len(proposed_ranks)) + 1
        rows.append({
            'seq_name': seq_name,
            'original_label': original_path,
            'predicted_label': proposed_path,
            'lwr': float(confidence),
            'mismatch_rank': mismatch_rank,
        })

with open(opts.mislabels_tsv, 'w') as fh:
    print('seq_name\\toriginal_label\\tpredicted_label\\tlwr\\tmismatch_rank\\tmethod', file=fh)
    for row in rows:
        if row['lwr'] >= opts.min_lwr:
            print(f"{row['seq_name']}\\t{row['original_label']}\\t{row['predicted_label']}\\t{row['lwr']}\\t{row['mismatch_rank']}\\tsativa", file=fh)

with open(opts.manifest_file) as fh:
    # n_folds is the number of leave-*batch*-out folds (25 by default, regardless
    # of input size) -- not one per sequence. n_leaves is the actual sequence count.
    n_leaves = json.load(fh)['n_leaves']

with open(opts.summary_txt, 'w') as fh:
    # .mis lists only flagged sequences, not every sequence scored -- n_leaves
    # from the taskdir's own manifest.json gives the honest total instead. Rows
    # below --min-lwr are still counted as scored, just not reported as mislabels.
    print(f"sequences scored: {n_leaves}", file=fh)
    print(f"min_lwr threshold: {opts.min_lwr}", file=fh)
    print(f"putative mislabels: {sum(1 for r in rows if r['lwr'] >= opts.min_lwr)}", file=fh)

with open('versions.yml', 'w') as fh:
    print('"${task.process}":', file=fh)
    print('    python: ' + sys.version.split()[0], file=fh)
PYEOF
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.mislabels.tsv ${prefix}.summary.txt
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """
}
