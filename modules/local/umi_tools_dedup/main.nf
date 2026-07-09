process UMI_DEDUP {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/umi_tools:1.1.6--py312h0fa9677_0' :
        'quay.io/biocontainers/umi_tools:1.1.6--py312h0fa9677_0'}"

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path('*.dedup.bam')            , emit: bam
    tuple val(meta), path('*.umi_tools_dedup.log')  , emit: log
    tuple val(meta), path('*.umi_tools_dedup*.tsv') , optional: true, emit: stats
    tuple val("${task.process}"), val("umi_tools"), eval("umi_tools --version 2>&1 | sed 's/.*version: //'"), topic: versions, emit: versions_umi_tools

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    umi_tools dedup \\
        $args \\
        -I $bam \\
        -S ${prefix}.dedup.bam \\
        --log=${prefix}.umi_tools_dedup.log \\
        --output-stats=${prefix}.umi_tools_dedup
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.dedup.bam
    touch ${prefix}.umi_tools_dedup.log
    touch ${prefix}.umi_tools_dedup_edit_distance.tsv
    touch ${prefix}.umi_tools_dedup_per_umi.tsv
    touch ${prefix}.umi_tools_dedup_per_umi_per_position.tsv
    """
}
