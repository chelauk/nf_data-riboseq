process SAMTOOLS_INDEX {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.20--h50ea8bc_1' :
        'quay.io/biocontainers/samtools:1.20--h50ea8bc_1'}"

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path(bam), path("${bam}.bai"), emit: bam_bai
    tuple val("${task.process}"), val('samtools'), eval("samtools --version | sed -n '1s/samtools //p'"), topic: versions, emit: versions_samtools

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    samtools index \\
        $args \\
        $bam \\
        ${bam}.bai
    """

    stub:
    """
    touch ${bam}.bai
    """
}
