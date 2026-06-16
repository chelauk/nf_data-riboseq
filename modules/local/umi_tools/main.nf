process UMI_TOOLS {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/umi_tools:1.1.6--py310h2b6aa90_4' :
        'quay.io/biocontainers/umi_tools:1.1.6--py310h2b6aa90_4'}"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path('*.umi.fastq.gz'), emit: reads
    tuple val(meta), path('*.log')          , emit: log
    tuple val("${task.process}"), val("umi_tools"), eval('umi_tools --version'), topic: versions, emit: versions_umi_tools

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def args2 = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    umi_tools extract \\
        $args \\
        $args2 \\
        -I $reads \\
        -S ${prefix}.umi.fastq.gz \\
        --log=${prefix}.umi_tools.log
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo '' | gzip > ${prefix}.umi.fastq.gz
    touch ${prefix}.umi_tools.log
    """
}
