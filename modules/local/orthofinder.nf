process OF_PREPARE_BLAST {
    tag "$meta.id"
    label 'process_low'
    
    conda (params.enable_conda ? "bioconda::orthofinder=2.5.4" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/orthofinder:2.5.4--hdfd78af_0':
        'quay.io/biocontainers/orthofinder:2.5.4--hdfd78af_0' }"

    input:

    tuple val(meta), path(aa_fasta)

    output:
    
    tuple val(meta), path("*.dmnd"), emit: dmnd
    tuple val(meta), path("*.fa"), emit: fa
    tuple val(meta), path('SpeciesIDs.txt'), emit: ids
    
    // TODO nf-core: List additional required output channels/values here
    path "versions.yml"           , emit: versions

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // TODO nf-core: Where possible, a command MUST be provided to obtain the version number of the software e.g. 1.10
    //               If the software is unable to output a version number on the command-line then it can be manually specified
    //               e.g. https://github.com/nf-core/modules/blob/master/modules/homer/annotatepeaks/main.nf
    //               Each software used MUST provide the software name and version number in the YAML version file (versions.yml)
    // TODO nf-core: It MUST be possible to pass additional parameters to the tool as a command-line string via the "task.ext.args" directive
    // TODO nf-core: If the tool supports multi-threading then you MUST provide the appropriate parameter
    //               using the Nextflow "task" variable e.g. "--threads $task.cpus"
    // TODO nf-core: Please replace the example samtools command below with your module's command
    // TODO nf-core: Please indent the command appropriately (4 spaces!!) to help with readability ;)
    """
    orthofinder \\
        -f $aa_fasta \\
        $args \\
        -t $task.cpus \\
        -op

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        orthofinder: \$(echo \$(orthofinder -h | head -2 | tail -1 | grep -o '[0-9]+.[0-9]+.[0-9]+'))
    END_VERSIONS
    """
}
