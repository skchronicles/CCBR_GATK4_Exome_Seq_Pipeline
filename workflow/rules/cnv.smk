# Rules to predict copy number variation
rule freec_exome_somatic_pass1:
    input: 
        normal = lambda w: [os.path.join(output_bamdir,"final_bams", pairs_dict[w.samples] + ".bam")],
        tumor = os.path.join(output_bamdir,"final_bams","{samples}.bam"),
    output: 
        cnvs = os.path.join(output_somatic_cnv, "freec_out", "pass1", "{samples}.recal.bam_CNVs.p.value.txt"),
    params: 
        targets = exome_targets_bed,
        normalsample = lambda w: [pairs_dict[w.samples]],
        tumorsample = "{samples}",
        fasta = config['references']['GENOME'],
        lengths = config['references']['FREECLENGTHS'],
        chroms = config['references']['FREECCHROMS'],
        pile = config['references']['FREECPILEUP'],
        snps = config['references']['FREECSNPS'],
        config_script = config['scripts']['freec_p1_config'],
        sig_script = config['scripts']['freec_significance'],
        plot_script = config['scripts']['freec_plot'],
        rname = 'freec1',
    envmodules: 
        'freec/11.5',
        'samtools/1.9',
        'bedtools/2.27.1',
        'R/3.6.1'
    container: config['images']['wes_base']
    shell: """
    myoutdir="$(dirname {output.cnvs})/{params.tumorsample}"
    if [ ! -d "$myoutdir" ]; then mkdir -p "$myoutdir"; fi
 
    perl "{params.config_script}" \\
        "$myoutdir" \\
        {params.lengths} \\
        {params.chroms} \\
        {input.tumor} \\
        {input.normal} \\
        {params.pile} \\
        {params.fasta} \\
        {params.snps} \\
        {params.targets}

    freec -conf "$myoutdir/freec_exome_config.txt"

    cat "{params.sig_script}" | \\
        R --slave \\
        --args $myoutdir/{params.tumorsample}.bam_CNVs \\
        $myoutdir/{params.tumorsample}.bam_ratio.txt

    mv $myoutdir/{params.tumorsample}.bam_CNVs.p.value.txt {output.cnvs}
    cat "{params.plot_script}" | \\
        R --slave \\
        --args 2 \\
        $myoutdir/{params.tumorsample}.bam_ratio.txt \\
        $myoutdir/{params.tumorsample}.bam_BAF.txt
    """


rule sequenza:
    input: 
        freeccnvs = os.path.join(output_somatic_cnv, "freec_out", "pass1", "{samples}.recal.bam_CNVs.p.value.txt"),
    output: 
        fit = os.path.join(output_somatic_cnv, "sequenza_out", "{samples}_alternative_solutions.txt"),
    params: 
        normalsample = lambda w: [pairs_dict[w.samples]],
        tumorsample = "{samples}",
        gc = config['references']['SEQUENZAGC'],
        run_script = config['scripts']['run_sequenza'],
        rname = 'sequenza'
    threads: 4
    envmodules:
        'sequenza-utils/2.2.0',
        'samtools/1.9',
        'R/3.6.1'
    container: config['images']['wes_base']
    shell: """
    myoutdir="$(dirname {output.fit})/{params.tumorsample}"
    if [ ! -d "$myoutdir" ]; then mkdir -p "$myoutdir"; fi

    gzip -c "$(dirname {input.freeccnvs})/{params.tumorsample}/{params.normalsample}.bam_minipileup.pileup" \\
        > "$myoutdir/{params.normalsample}.recal.bam_minipileup.pileup.gz"
    gzip -c "$(dirname {input.freeccnvs})/{params.tumorsample}/{params.tumorsample}.bam_minipileup.pileup" \\
        > "$myoutdir/{params.tumorsample}.recal.bam_minipileup.pileup.gz"
    
    sequenza-utils bam2seqz \\
        -p \\
        -gc {params.gc} \\
        -n "$myoutdir/{params.normalsample}.recal.bam_minipileup.pileup.gz" \\
        -t "$myoutdir/{params.tumorsample}.recal.bam_minipileup.pileup.gz" \\
        | gzip > "$myoutdir/{params.tumorsample}.seqz.gz"

    sequenza-utils seqz_binning \\
        -w 100 \\
        -s "$myoutdir/{params.tumorsample}.seqz.gz" \\
        | tee "$myoutdir/{params.tumorsample}.bin100.seqz" \\
        | gzip > "$myoutdir/{params.tumorsample}.bin100.seqz.gz"

    Rscript "{params.run_script}" \\
        "$myoutdir/{params.tumorsample}.bin100.seqz" \\
        "$myoutdir" \\
        "{params.normalsample}+{params.tumorsample}" \\
        {threads}

    mv "$myoutdir/{params.normalsample}+{params.tumorsample}_alternative_solutions.txt" "{output.fit}"
    rm "$myoutdir/{params.tumorsample}.bin100.seqz"
    """


rule freec_exome_somatic_pass2:
    input:
        normal = lambda w: [os.path.join(output_bamdir,"final_bams", pairs_dict[w.samples] + ".bam")],
        tumor = os.path.join(output_bamdir,"final_bams","{samples}.bam"),
        fit = os.path.join(output_somatic_cnv, "sequenza_out", "{samples}_alternative_solutions.txt"),
    output:
        cnvs = os.path.join(output_somatic_cnv, "freec_out", "pass2", "{samples}.recal.bam_CNVs.p.value.txt"),
    params:
        targets = exome_targets_bed,
        normalsample = lambda w: [pairs_dict[w.samples]],
        tumorsample = "{samples}",
        fasta = config['references']['GENOME'],
        lengths = config['references']['FREECLENGTHS'],
        chroms = config['references']['FREECCHROMS'],
        pile = config['references']['FREECPILEUP'],
        snps = config['references']['FREECSNPS'],
        config_script = config['scripts']['freec_p2_config'],
        sig_script = config['scripts']['freec_significance'],
        plot_script = config['scripts']['freec_plot'],
        rname = 'freec',
    envmodules:
        'freec/11.5',
        'samtools/1.9',
        'bedtools/2.27.1',
        'R/3.6.1',
    container: config['images']['wes_base']
    shell: """
    myoutdir="$(dirname {output.cnvs})/{params.tumorsample}"
    if [ ! -d "$myoutdir" ]; then mkdir -p "$myoutdir"; fi

    perl {params.config_script} \\
        "$myoutdir" \\
        {params.lengths} \\
        {params.chroms} \\
        {input.tumor} \\
        {input.normal} \\
        {params.pile} \\
        {params.fasta} \\
        {params.snps} \\
        {params.targets} \\
        {input.fit}

    freec -conf "$myoutdir/freec_exome_config.txt"

    cat "{params.sig_script}" | \\
        R --slave \\
        --args $myoutdir/{params.tumorsample}.bam_CNVs \\
        $myoutdir/{params.tumorsample}.bam_ratio.txt
   
    mv $myoutdir/{params.tumorsample}.bam_CNVs.p.value.txt {output.cnvs}
    cat "{params.plot_script}" | \\
        R --slave \\
        --args 2 \\
        $myoutdir/{params.tumorsample}.bam_ratio.txt \\
        $myoutdir/{params.tumorsample}.bam_BAF.txt
    """
