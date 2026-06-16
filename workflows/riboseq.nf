/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { CUTADAPT as CUTADAPT_1 } from '../modules/nf-core/cutadapt/main'
include { UMI_TOOLS              } from '../modules/local/umi_tools/main'
include { CUTADAPT as CUTADAPT_2 } from '../modules/nf-core/cutadapt/main'
include { BOWTIE2_ALIGN as BOWTIE_rRNA } from '../modules/nf-core/bowtie2/align/main'
include { BOWTIE2_ALIGN as BOWTIE_tRNA } from '../modules/nf-core/bowtie2/align/main'
include { BOWTIE2_ALIGN as BOWTIE_snRNA } from '../modules/nf-core/bowtie2/align/main'
include { STAR_ALIGN             } from '../modules/nf-core/star/align/main'
include { RIBOWALTZ              } from '../modules/nf-core/ribowaltz/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_riboseq_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow RIBOSEQ {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir
    bowtie2_rRNA
    bowtie2_tRNA
    bowtie2_snRNA

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()
    //
    // MODULE: Run FastQC
    //
    FASTQC(ch_samplesheet)
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.map{ _meta, file -> file })

    // 
    // MODULE: Run Cutadapt
    //
    // First the Linker MC+ (MC+) is trimmed from the 3’ end of each read and only reads 
    // longer than X+9nt are retained, while shorter reads are discarded
    CUTADAPT_1(ch_samplesheet)
    ch_multiqc_files = ch_multiqc_files.mix(CUTADAPT_1.out.log.map{ _meta, file -> file })

    //The sequence of the 5’ and 3’ UMIs are moved from the read sequence to the read name
    //
    // MODULE: Extract UMIs
    //
    UMI_TOOLS(CUTADAPT_1.out.reads)
    ch_multiqc_files = ch_multiqc_files.mix(UMI_TOOLS.out.log.map{ _meta, file -> file })
    
    // The T preceding the RPF is then removed:
    //
    // MODULE: CUTADAPT_2
    //
    CUTADAPT_2(UMI_TOOLS.out.reads)
    ch_multiqc_files = ch_multiqc_files.mix(CUTADAPT_2.out.log.map{ _meta, file -> file })

    //
    // MODULE: Align to rRNA, tRNA and snRNA reference sequences
    //
    if (!bowtie2_rRNA || !bowtie2_tRNA || !bowtie2_snRNA) {
        error "Bowtie2 riboseq indexes are required. Set --genome GRCh38 or provide --bowtie2_rRNA, --bowtie2_tRNA and --bowtie2_snRNA."
    }
    ch_bowtie2_rrna_index = Channel.value([[id: 'rRNA'], file(bowtie2_rRNA, checkIfExists: true)])
    ch_bowtie2_trna_index = Channel.value([[id: 'tRNA'], file(bowtie2_tRNA, checkIfExists: true)])
    ch_bowtie2_snrna_index = Channel.value([[id: 'snRNA'], file(bowtie2_snRNA, checkIfExists: true)]) 
    
    BOWTIE_rRNA(CUTADAPT_2.out.reads, ch_bowtie2_rrna_index, [], true, false)
    ch_multiqc_files = ch_multiqc_files.mix(BOWTIE_rRNA.out.log.map{ _meta, file -> file })
    BOWTIE_tRNA(BOWTIE_rRNA.out.fastq, ch_bowtie2_trna_index, [], true, false)
    ch_multiqc_files = ch_multiqc_files.mix(BOWTIE_tRNA.out.log.map{ _meta, file -> file })
    BOWTIE_snRNA(BOWTIE_tRNA.out.fastq, ch_bowtie2_snrna_index, [], true, false)
    ch_multiqc_files = ch_multiqc_files.mix(BOWTIE_snRNA.out.log.map{ _meta, file -> file })

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'riboseq_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'riboseq'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )
    emit:multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
