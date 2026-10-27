process RAXMLNG_MOOSE {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/raxml-ng:2.0.3--h870a6a7_0' :
        'quay.io/biocontainers/raxml-ng:2.0.3--h870a6a7_0' }"

    input:
    tuple val(meta), path(alignment)

    output:
    tuple val(meta), path("*.raxml.moose.bestModel"), emit: best_model
    tuple val(meta), path("*.raxml.log")            , emit: log
    tuple val("${task.process}"), val('raxmlng'), eval("raxml-ng --version 2>&1 | sed '/RAxML-NG v/!d;s/.*v. //;s/ .*//'"), emit: versions_raxmlng, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    if (!(args ==~ /.*--seed.*/)) {args += " --seed=42"}
    """
    raxml-ng \\
        --moose \\
        ${args} \\
        --msa ${alignment} \\
        --threads ${task.cpus} \\
        --prefix ${prefix}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "GTR+FO+G4, noname = 1-1" > ${prefix}.raxml.moose.bestModel
    touch ${prefix}.raxml.log
    """
}
