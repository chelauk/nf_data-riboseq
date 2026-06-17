process BOWTIE2_ALIGN {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bowtie2:2.5.4--he96a11b_6' :
        'quay.io/biocontainers/bowtie2:2.5.4--he96a11b_6' }"

    input:
    tuple val(meta) , path(reads)
    tuple val(meta2), path(index)

    output:
    tuple val(meta), path("*.log")      , emit: log
    tuple val(meta), path("*.unmapped.fastq.gz"), emit: fastq
    tuple val("${task.process}"), val('bowtie2'), eval("bowtie2 --version 2>&1 | sed -n 's/.*bowtie2-align-s version //p'"), emit: versions_bowtie2, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ""
    def prefix = task.ext.prefix ?: "${meta.id}.${meta2.id}"

    """
    INDEX=`find -L ./ -name "*.rev.1.bt2" | sed "s/\\.rev.1.bt2\$//"`
    [ -z "\$INDEX" ] && INDEX=`find -L ./ -name "*.rev.1.bt2l" | sed "s/\\.rev.1.bt2l\$//"`
    [ -z "\$INDEX" ] && echo "Bowtie2 index files not found" 1>&2 && exit 1
    [ "\$(basename "${reads}")" = "${prefix}.unmapped.fastq.gz" ] && echo "Bowtie2 input and output FASTQ paths are identical" 1>&2 && exit 1

    bowtie2 \\
        --threads $task.cpus \\
        ${args} \\
        -U $reads \\
        -x \$INDEX \\
        --un-gz ${prefix}.unmapped.fastq.gz \\
        -S /dev/null \\
        2>| >(tee ${prefix}.bowtie2.log >&2)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}.${meta2.id}"

    """
    touch ${prefix}.bowtie2.log
    echo | gzip > ${prefix}.unmapped.fastq.gz
    """

}
