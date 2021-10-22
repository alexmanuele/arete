////////////////////////////////////////////////////
/* --         LOCAL PARAMETER VALUES           -- */
////////////////////////////////////////////////////

params.summary_params = [:]

////////////////////////////////////////////////////
/* --          VALIDATE INPUTS                 -- */
////////////////////////////////////////////////////

// Validate input parameters
//Workflow.validateWorkflowParams(params, log)

// TODO nf-core: Add all file path parameters for the pipeline to the list below
// Check input path parameters to see if they exist
def checkPathParamList = [ params.input_sample_table, params.multiqc_config, params.reference_genome ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
//if (params.input_sample_table) { ch_input = file(params.input_sample_table) } else { exit 1, 'Input samplesheet not specified!' }
//if (params.reference_genome) { ch_reference_genome = file(params.reference_genome) } else { exit 1, 'Reference genome not specified!' }
//if (params.outgroup_genome ) { ch_outgroup_genome = file(params.outgroup_genome) } else { ch_outgroup_genome = '' }

////////////////////////////////////////////////////
/* --          CONFIG FILES                    -- */
////////////////////////////////////////////////////

ch_multiqc_config        = file("$projectDir/assets/multiqc_config.yaml", checkIfExists: true)
ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config) : Channel.empty()

////////////////////////////////////////////////////
/* --       IMPORT MODULES / SUBWORKFLOWS      -- */
////////////////////////////////////////////////////

// Don't overwrite global params.modules, create a copy instead and use that within the main script.
def modules = params.modules.clone()

def multiqc_options   = modules['multiqc']
multiqc_options.args += params.multiqc_title ? " --title \"$params.multiqc_title\"" : ''

// Modules: local
include { GET_SOFTWARE_VERSIONS } from '../modules/local/get_software_versions'   addParams( options: [publish_files : ['csv':'']] )

// Modules: nf-core/modules
include { FASTQC                } from '../modules/nf-core/software/fastqc/main'  addParams( options: modules['fastqc']            )
include { FASTQC as TRIM_FASTQC } from '../modules/nf-core/software/fastqc/main'  addParams( options: modules['fastqc']            )
include { FASTP                 } from '../modules/nf-core/software/fastp/main'  addParams( options: [:]                          )
include { UNICYCLER             } from '../modules/nf-core/software/unicycler/main'  addParams( options: [:] )
include { QUAST                 } from '../modules/nf-core/software/quast/main'  addParams( options: [:]                          )
include { MULTIQC               } from '../modules/nf-core/software/multiqc/main' addParams( options: multiqc_options              )
include { KRAKEN2_DB;
          KRAKEN2_RUN           } from '../modules/nf-core/software/kraken2/run/main' addParams( options: [:] )
include { PROKKA                } from '../modules/nf-core/software/prokka/main' addParams( options: [:] )
//include { ABRICATE as ABRICATE_VF;
//          UPDATE_ABRICATE_DB as ABRICATE_VF_DB} from '../modules/local/software/abricate/main' addParams( options: [:] )
//include { ABRICATE as ABRICATE_BCM2;
//          UPDATE_ABRICATE_DB as ABRICATE_BCM2_DB} from '../modules/local/software/abricate/main' addParams( options: [:] )
include { GET_CAZYDB;
          GET_VFDB;
          GET_BACMET} from '../modules/local/blast_databases.nf'
include { DIAMOND_MAKEDB as DIAMOND_MAKE_CAZY;
          DIAMOND_MAKEDB as DIAMOND_MAKE_VFDB;
          DIAMOND_MAKEDB as DIAMOND_MAKE_BACMET;
          DIAMOND_BLASTX as DIAMOND_BLAST_CAZY;
          DIAMOND_BLASTX as DIAMOND_BLAST_VFDB;
          DIAMOND_BLASTX as DIAMOND_BLAST_BACMET} from '../modules/local/software/diamond/main'
include { RGI;
          UPDATE_RGI_DB } from '../modules/local/software/rgi/main' addParams( options: [:] )
//include { SNIPPY;
          //SNIPPY_CTG;
          //SNIPPY_CORE } from '../modules/local/software/snippy/main' addParams( options: [:] )
include { GET_NCBI_AMR_HMM;
          PATHRACER } from '../modules/local/software/pathracer/main' addParams( options: [:] )
include { MOB_INIT;
          MOB_RECON } from '../modules/local/software/mobsuite/main' addParams( options: [:] )
//include { CRISPRCASFINDER } from '../modules/local/software/crisprcasfinder/main' addParams( options: [:] )
include { IQTREE } from '../modules/local/software/iqtree/main' addParams( options: [:] )
include { ROARY } from '../modules/local/software/roary/main'

// Subworkflows: local
include { INPUT_CHECK;
          ANNOTATION_INPUT_CHECK } from '../subworkflows/local/input_check'        addParams( options: [:]                          )

////////////////////////////////////////////////////
/* --           RUN MAIN WORKFLOW              -- */
////////////////////////////////////////////////////

// Info required for completion email and summary
def multiqc_report = []

workflow ARETE {

    // Check mandatory parameters
    if (params.input_sample_table) { ch_input = file(params.input_sample_table) } else { exit 1, 'Input samplesheet not specified!' }
    if (params.reference_genome) { ch_reference_genome = file(params.reference_genome) } else { exit 1, 'Reference genome not specified!' }
    if (params.outgroup_genome ) { ch_outgroup_genome = file(params.outgroup_genome) } else { ch_outgroup_genome = '' }

    ch_software_versions = Channel.empty()

    /*
     * SUBWORKFLOW: Read in samplesheet, validate and stage input files
     */
    INPUT_CHECK(ch_input)


    /////////////////// Read Processing /////////////////////////////
    /*
     * MODULE: Run FastQC
     */
    FASTQC(INPUT_CHECK.out.reads, "raw_fastqc")
    ch_software_versions = ch_software_versions.mix(FASTQC.out.version.first().ifEmpty(null))

    /*
     * MODULE: Trim Reads
     */
    FASTP(INPUT_CHECK.out.reads)
    ch_software_versions = ch_software_versions.mix(FASTP.out.version.first().ifEmpty(null))

    /*
     * MODULE: Run FastQC on trimmed reads
     */
    TRIM_FASTQC(FASTP.out.reads, "trim_fastqc")
    ch_software_versions = ch_software_versions.mix(TRIM_FASTQC.out.version.first().ifEmpty(null))

    ///*
    // * MODULE: Run Kraken2
    // */
    KRAKEN2_DB()
    KRAKEN2_RUN(FASTP.out.reads, KRAKEN2_DB.out.minikraken)
    ch_software_versions = ch_software_versions.mix(KRAKEN2_RUN.out.version.first().ifEmpty(null))


    /////////////////// ASSEMBLE /////////////////////////////
    /*
     * MODULE: Assembly
     */
    UNICYCLER(FASTP.out.reads)
    ch_software_versions = ch_software_versions.mix(UNICYCLER.out.version.first().ifEmpty(null))

    /*
     * Module: Evaluate Assembly
     */
    QUAST(UNICYCLER.out.scaffolds, ch_reference_genome)
    ch_software_versions = ch_software_versions.mix(QUAST.out.version.first().ifEmpty(null))


    /////////////////// ANNOTATION ///////////////////////////
    /*
     * Module: Annotate AMR
     */
    UPDATE_RGI_DB()
    ch_software_versions = ch_software_versions.mix(UPDATE_RGI_DB.out.card_version.ifEmpty(null))
    RGI(UNICYCLER.out.scaffolds, UPDATE_RGI_DB.out.card_json)
    ch_software_versions = ch_software_versions.mix(RGI.out.version.first().ifEmpty(null))

    /*
     *  Module: Annotate graph with pathracer
     */
    //GET_NCBI_AMR_HMM()
    //PATHRACER(UNICYCLER.out.raw_gfa, GET_NCBI_AMR_HMM.out.hmm);

    /*
     * Module: Prokka
     */
    PROKKA(UNICYCLER.out.scaffolds)
    ch_software_versions = ch_software_versions.mix(PROKKA.out.version.first().ifEmpty(null))

    /*
     * Module: Mob-Suite
     */
    MOB_RECON(UNICYCLER.out.scaffolds)
    ch_software_versions = ch_software_versions.mix(MOB_RECON.out.version.first().ifEmpty(null))

    /*
     * Module: BLAST vs CAZY, VFDB, Bacmet
     */
    GET_CAZYDB()
    GET_BACMET()
    GET_VFDB()
    DIAMOND_MAKE_CAZY(GET_CAZYDB.out.cazydb)
    ch_software_versions = ch_software_versions.mix(DIAMOND_MAKE_CAZY.out.version.ifEmpty(null))
    DIAMOND_BLAST_CAZY(PROKKA.out.ffn, DIAMOND_MAKE_CAZY.out.db, "CAZYDB")

    DIAMOND_MAKE_VFDB(GET_VFDB.out.vfdb)
    DIAMOND_BLAST_VFDB(PROKKA.out.ffn, DIAMOND_MAKE_VFDB.out.db, "VFDB")

    DIAMOND_MAKE_BACMET(GET_BACMET.out.bacmet)
    DIAMOND_BLAST_BACMET(PROKKA.out.ffn, DIAMOND_MAKE_BACMET.out.db, "BACMET")


    ////////////////////////// PANGENOME /////////////////////////////////////
    /*
    * Module: Roary
    */
    ROARY(PROKKA.out.gff.collect{it[1]})
    ch_software_versions = ch_software_versions.mix(ROARY.out.version.ifEmpty(null))


    ////////////////////////// PHYLO ////////////////////////////////////////
    /*
     * Module: Snippy
     */
    //SNIPPY(FASTP.out.reads, ch_reference_genome)
    //SNIPPY_CTG(ch_outgroup_genome, ch_reference_genome)
    //ch_snippy_folders = SNIPPY.out.snippy_folder.mix(SNIPPY_CTG.out.snippy_folder).collect()
    //SNIPPY_CORE(ch_snippy_folders, ch_reference_genome)
    //ch_software_versions = ch_software_versions.mix(SNIPPY_CORE.out.version.ifEmpty(null))

    /*
     * Module: IQTree
     */
    //IQTREE(SNIPPY_CORE.out.var_aln, SNIPPY_CORE.out.base_freq)
    //ch_software_versions = ch_software_versions.mix(IQTREE.out.version.ifEmpty(null))
    
    //TODO IQTree with roary
    //IQTREE(ROARY.out.roary_core_gene_alignment)
    //ch_software_versions = ch_software_versions.mix(IQTREE.out.version.ifEmpty(null))


    ////////////////////////// REPORTING /////////////////////////////////////
    /*
     * MODULE: Pipeline reporting
     */
    // Get unique list of files containing version information
    ch_software_versions
        .map { it -> if (it) [ it.baseName, it ] }
        .groupTuple()
        .map { it[1][0] }
        .flatten()
        .collect()
        .set { ch_software_versions }
    GET_SOFTWARE_VERSIONS(ch_software_versions)

    /*
     * MODULE: MultiQC
     */
    workflow_summary    = Workflow.paramsSummaryMultiqc(workflow, params.summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    //Mix QUAST results into one report file

    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(Channel.from(ch_multiqc_config))
    ch_multiqc_files = ch_multiqc_files.mix(ch_multiqc_custom_config.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(GET_SOFTWARE_VERSIONS.out.yaml.collect())
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(TRIM_FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(KRAKEN2_RUN.out.txt.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(QUAST.out.tsv.collect())
    ch_multiqc_files = ch_multiqc_files.mix(PROKKA.out.txt.collect{it[1]}.ifEmpty([]))

    MULTIQC(ch_multiqc_files.collect())
    multiqc_report       = MULTIQC.out.report.toList()
    ch_software_versions = ch_software_versions.mix(MULTIQC.out.version.ifEmpty(null))

}

////////////////////////////////////////////////////
/* --              COMPLETION EMAIL            -- */
////////////////////////////////////////////////////

workflow.onComplete {
    //Completion.email(workflow, params, params.summary_params, projectDir, log, multiqc_report)
    Completion.summary(workflow, params, log)
}

////////////////////////////////////////////////////
/* --                  THE END                 -- */
///////////////////////////////////////////////////


////////////////////////////////////////////////////
/* --              Workflow Subsets           -- */
///////////////////////////////////////////////////


////////////////////////////////////////////////////
/* --       Assembly: Raw -> Prokka            -- */
///////////////////////////////////////////////////
workflow ASSEMBLY{

    ch_software_versions = Channel.empty()

    /*
     * SUBWORKFLOW: Read in samplesheet, validate and stage input files
     */
    INPUT_CHECK(ch_input)


    /////////////////// Read Processing /////////////////////////////
    /*
     * MODULE: Run FastQC
     */
    FASTQC(INPUT_CHECK.out.reads, "raw_fastqc")
    ch_software_versions = ch_software_versions.mix(FASTQC.out.version.first().ifEmpty(null))

    /*
     * MODULE: Trim Reads
     */
    FASTP(INPUT_CHECK.out.reads)
    ch_software_versions = ch_software_versions.mix(FASTP.out.version.first().ifEmpty(null))

    /*
     * MODULE: Run FastQC on trimmed reads
     */
    TRIM_FASTQC(FASTP.out.reads, "trim_fastqc")
    ch_software_versions = ch_software_versions.mix(TRIM_FASTQC.out.version.first().ifEmpty(null))

    ///*
    // * MODULE: Run Kraken2
    // */
    KRAKEN2_DB()
    KRAKEN2_RUN(FASTP.out.reads, KRAKEN2_DB.out.minikraken)
    ch_software_versions = ch_software_versions.mix(KRAKEN2_RUN.out.version.first().ifEmpty(null))


    /////////////////// ASSEMBLE /////////////////////////////
    /*
     * MODULE: Assembly
     */
    UNICYCLER(FASTP.out.reads)
    ch_software_versions = ch_software_versions.mix(UNICYCLER.out.version.first().ifEmpty(null))

    /*
     * Module: Evaluate Assembly
     */
    QUAST(UNICYCLER.out.scaffolds, ch_reference_genome)
    ch_software_versions = ch_software_versions.mix(QUAST.out.version.first().ifEmpty(null))


    /////////////////// ANNOTATION ///////////////////////////
    /*
     * Module: Prokka
     */
    PROKKA(UNICYCLER.out.scaffolds)
    ch_software_versions = ch_software_versions.mix(PROKKA.out.version.first().ifEmpty(null))



    ////////////////////////// REPORTING /////////////////////////////////////
    /*
     * MODULE: Pipeline reporting
     */
    // Get unique list of files containing version information
    ch_software_versions
        .map { it -> if (it) [ it.baseName, it ] }
        .groupTuple()
        .map { it[1][0] }
        .flatten()
        .collect()
        .set { ch_software_versions }
    GET_SOFTWARE_VERSIONS(ch_software_versions)

    /*
     * MODULE: MultiQC
     */
    workflow_summary    = Workflow.paramsSummaryMultiqc(workflow, params.summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(Channel.from(ch_multiqc_config))
    ch_multiqc_files = ch_multiqc_files.mix(ch_multiqc_custom_config.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(GET_SOFTWARE_VERSIONS.out.yaml.collect())
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(TRIM_FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(KRAKEN2_RUN.out.txt.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(QUAST.out.tsv.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(PROKKA.out.log.collect{it[1]}.ifEmpty([]))

    MULTIQC(ch_multiqc_files.collect())
    multiqc_report       = MULTIQC.out.report.toList()
    ch_software_versions = ch_software_versions.mix(MULTIQC.out.version.ifEmpty(null))

}

// Assemblies -> Annotations.
workflow ANNOTATION {
    // Check mandatory parameters
    if (params.input_sample_table) { ch_input = file(params.input_sample_table) } else { exit 1, 'Input samplesheet not specified!' }

    ch_software_versions = Channel.empty()

    /*
     * SUBWORKFLOW: Read in samplesheet, validate and stage input files
     */
    ANNOTATION_INPUT_CHECK(ch_input)

    //Instead of QC here, move QC to the assembly workflow.
    //TODO clear with team and delete this module.
    /*
     * Module: Evaluate Assembly
     */
    //QUAST(UNICYCLER.out.scaffolds, ch_reference_genome)
    //ch_software_versions = ch_software_versions.mix(QUAST.out.version.first().ifEmpty(null))


    /////////////////// ANNOTATION ///////////////////////////
    /*
     * Module: Annotate AMR
     */
    UPDATE_RGI_DB()
    ch_software_versions = ch_software_versions.mix(UPDATE_RGI_DB.out.card_version.ifEmpty(null))
    RGI(ANNOTATION_INPUT_CHECK.out.genomes, UPDATE_RGI_DB.out.card_json)
    ch_software_versions = ch_software_versions.mix(RGI.out.version.first().ifEmpty(null))

    /*
     *  Module: Annotate graph with pathracer
     */
    // TODO figure out how this works with pre-existing genomes....
    //GET_NCBI_AMR_HMM()
    //PATHRACER(UNICYCLER.out.raw_gfa, GET_NCBI_AMR_HMM.out.hmm);

    /*
     * Module: Prokka
     */
    PROKKA(ANNOTATION_INPUT_CHECK.out.genomes)
    ch_software_versions = ch_software_versions.mix(PROKKA.out.version.first().ifEmpty(null))

    /*
     * Module: Mob-Suite
     */
    MOB_RECON(ANNOTATION_INPUT_CHECK.out.genomes)
    ch_software_versions = ch_software_versions.mix(MOB_RECON.out.version.first().ifEmpty(null))

    /*
     * Module: BLAST vs CAZY, VFDB, Bacmet
     */
    GET_CAZYDB()
    GET_BACMET()
    GET_VFDB()
    DIAMOND_MAKE_CAZY(GET_CAZYDB.out.cazydb)
    ch_software_versions = ch_software_versions.mix(DIAMOND_MAKE_CAZY.out.version.ifEmpty(null))
    DIAMOND_BLAST_CAZY(PROKKA.out.ffn, DIAMOND_MAKE_CAZY.out.db, "CAZYDB")

    DIAMOND_MAKE_VFDB(GET_VFDB.out.vfdb)
    DIAMOND_BLAST_VFDB(PROKKA.out.ffn, DIAMOND_MAKE_VFDB.out.db, "VFDB")

    DIAMOND_MAKE_BACMET(GET_BACMET.out.bacmet)
    DIAMOND_BLAST_BACMET(PROKKA.out.ffn, DIAMOND_MAKE_BACMET.out.db, "BACMET")


    ////////////////////////// PANGENOME /////////////////////////////////////
    /*
    * Module: Roary
    */
    ROARY(PROKKA.out.gff.collect{it[1]})
    ch_software_versions = ch_software_versions.mix(ROARY.out.version.ifEmpty(null))


    ////////////////////////// PHYLO ////////////////////////////////////////
    /*
     * Module: IQTree
     */
    //IQTREE(SNIPPY_CORE.out.var_aln, SNIPPY_CORE.out.base_freq)
    //ch_software_versions = ch_software_versions.mix(IQTREE.out.version.ifEmpty(null))
    
    //TODO IQTree with roary
    IQTREE(ROARY.out.roary_core_gene_alignment)
    ch_software_versions = ch_software_versions.mix(IQTREE.out.version.ifEmpty(null))


    ////////////////////////// REPORTING /////////////////////////////////////
    /*
     * MODULE: Pipeline reporting
     */
    // Get unique list of files containing version information
    ch_software_versions
        .map { it -> if (it) [ it.baseName, it ] }
        .groupTuple()
        .map { it[1][0] }
        .flatten()
        .collect()
        .set { ch_software_versions }
    GET_SOFTWARE_VERSIONS(ch_software_versions)

    /*
     * MODULE: MultiQC
     */
    workflow_summary    = Workflow.paramsSummaryMultiqc(workflow, params.summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    //Mix QUAST results into one report file

    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(Channel.from(ch_multiqc_config))
    ch_multiqc_files = ch_multiqc_files.mix(ch_multiqc_custom_config.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(GET_SOFTWARE_VERSIONS.out.yaml.collect())
    //ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    //ch_multiqc_files = ch_multiqc_files.mix(TRIM_FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    //ch_multiqc_files = ch_multiqc_files.mix(KRAKEN2_RUN.out.txt.collect{it[1]}.ifEmpty([]))
    //ch_multiqc_files = ch_multiqc_files.mix(QUAST.out.tsv.collect())
    ch_multiqc_files = ch_multiqc_files.mix(PROKKA.out.txt.collect{it[1]}.ifEmpty([]))

    MULTIQC(ch_multiqc_files.collect())
    multiqc_report       = MULTIQC.out.report.toList()
    ch_software_versions = ch_software_versions.mix(MULTIQC.out.version.ifEmpty(null))

}