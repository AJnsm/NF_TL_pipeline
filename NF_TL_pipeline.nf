#!/usr/bin/env nextflow

cellTypes_ch = Channel.from(params.clusterArray) 

process makeData {

    publishDir "${launchDir}/plots", mode: 'copy', pattern: '*.png'
    publishDir "${launchDir}/embeddings", mode: 'copy', pattern: '*coords.csv'

    input:
    path dataScript from "${projectDir}/pipelineScripts/makeTrainingData.py" 
    val cellType from cellTypes_ch
    path rawData from params.rawDataPath
    path clusterFile from params.clusterFile
    path doubletFile from params.doubletFile
    path userGenes from params.userGenes
    
    output:
    path "trainingData_*Genes.csv" into dataSets mode flatten
    path "*.png" optional true into plots
    path "*coords.csv" optional true into embeddings
    

    script:
    if( params.dataType == 'agnostic' )
        """
        python ${dataScript} --dataType ${params.dataType} --rawData ${rawData} --clusters ${clusterFile} --nGenes ${params.nGenes} --nCells ${params.nCells} --cluster ${cellType} --bcDoublets ${doubletFile} --userGenes ${userGenes} --twoReplicates ${params.twoReplicates}
        """

    else if( params.dataType == 'expression' )
        """
        python ${dataScript} --dataType ${params.dataType} --rawData ${rawData} --clusters ${clusterFile} --nGenes ${params.nGenes} --nCells ${params.nCells} --cluster ${cellType} --bcDoublets ${doubletFile} --userGenes ${userGenes} --twoReplicates ${params.twoReplicates}
        """
    else
        error "Invalid data type"
}

process estimatePCgraph {

    
    publishDir "${launchDir}/output", mode: 'copy'

    input:
    path PCgraphEstScript from "${projectDir}/pipelineScripts/parallelPCscript.R" 
    path dataSet from dataSets

    output:
    tuple path(dataSet), path('PCgraph*.csv') into PCgraphs_forMCMC_ch mode flatten
    tuple path(dataSet), path('CTRLgraph*.csv') into CTRLgraphs_ch mode flatten

    """
    Rscript ${PCgraphEstScript} ${dataSet} ${params.cores_PC} ${params.PCalpha}
    """
 }

process iterMCMCscheme {

    
    publishDir "${launchDir}/output", mode: 'copy'
    
    input:
    path MCMCscript from "${projectDir}/pipelineScripts/iterMCMCscript.R" 
    tuple path(dataSet), path(PCgraph) from PCgraphs_forMCMC_ch

    output:
    tuple path(dataSet), path('*graph*.csv') into MCMCgraphs_ch mode flatten

    """
    Rscript ${MCMCscript} ${PCgraph} ${dataSet} ${params.nGenes} 
    """
}

data_and_graphs_ch = CTRLgraphs_ch.mix(MCMCgraphs_ch)
data_and_graphs_ch.into {data_and_graphs_1pts; data_and_graphs_2pts; data_and_graphs_3pts; data_and_graphs_HOIs_MB; data_and_graphs_HOIs_67}


process estimateCoups_1pts {
    label 'interactionEstimation'    
    
    publishDir "${launchDir}/coupling_output", mode: 'copy'

    input:
    path estimationScript from "${projectDir}/pipelineScripts/estimateTLcoups.py" 
    path utilities from "${projectDir}/pipelineScripts/utilities.py" 
    path genesToOne from params.genesToOne
    tuple path(dataSet), path(graph) from data_and_graphs_1pts
    
    output:
    path 'interactions*.npy' into interaction_1pts_ch
    

    """
    python ${estimationScript} --dataPath ${dataSet} --graphPath ${graph} --intOrder 1 --nResamps ${params.bsResamps} --nCores ${params.cores_1pt} --estimationMethod ${params.estimationMethod} --edgeListAlpha ${params.edgeListAlpha} --genesToOne ${genesToOne} --dataDups ${params.dataDups} --boundBool ${params.boundBool}
    """

}


process estimateCoups_2pts {
    label 'interactionEstimation'
    
    publishDir "${launchDir}/coupling_output", mode: 'copy'

    input:
    path estimationScript from "${projectDir}/pipelineScripts/estimateTLcoups.py" 
    path utilities from "${projectDir}/pipelineScripts/utilities.py" 
    path genesToOne from params.genesToOne
    tuple path(dataSet), path(graph) from data_and_graphs_2pts
    
    output:
    path 'interactions*.npy' into interaction_2pts_ch
    path 'edgeList*.csv' into interaction_2pts_ch_edgeList

    """
    python ${estimationScript} --dataPath ${dataSet} --graphPath ${graph} --intOrder 2 --nResamps ${params.bsResamps} --nCores ${params.cores_2pt} --estimationMethod ${params.estimationMethod} --edgeListAlpha ${params.edgeListAlpha} --genesToOne ${genesToOne} --dataDups ${params.dataDups} --boundBool ${params.boundBool}
    """

}


process estimateCoups_3pts {
    label 'interactionEstimation'
    
    publishDir "${launchDir}/coupling_output", mode: 'copy'

    input:
    path estimationScript from "${projectDir}/pipelineScripts/estimateTLcoups.py" 
    path utilities from "${projectDir}/pipelineScripts/utilities.py" 
    path genesToOne from params.genesToOne
    tuple path(dataSet), path(graph) from data_and_graphs_3pts
    
    output:
    path 'interactions*.npy' into interaction_3pts_ch
    path 'edgeList*.csv' into interaction_3pts_ch_edgeList

    """
    python ${estimationScript} --dataPath ${dataSet} --graphPath ${graph} --intOrder 3 --nResamps ${params.bsResamps} --nCores ${params.cores_3pt} --estimationMethod ${params.estimationMethod} --edgeListAlpha ${params.edgeListAlpha} --genesToOne ${genesToOne} --dataDups ${params.dataDups} --boundBool ${params.boundBool}
    """

}


process estimateCoups_345pts_WithinMB {
    label 'interactionEstimation'
    
    publishDir "${launchDir}/coupling_output", mode: 'copy'

    input:
    path estimationScript from "${projectDir}/pipelineScripts/calcHOIsWithinMB.py" 
    path genesToOne from params.genesToOne
    tuple path(dataSet), path(graph) from data_and_graphs_HOIs_MB
    
    output:
    path 'interactions*.npy' into interaction_withinMB

    """
    python ${estimationScript} --dataPath ${dataSet} --graphPath ${graph} --nResamps ${params.bsResamps} --nCores ${params.cores_HOIs} --nRandoms ${params.nRandomHOIs}--genesToOne ${genesToOne} --dataDups ${params.dataDups} --boundBool ${params.boundBool}
    """

}


// process estimateCoups_6n7pts {
//     label 'interactionEstimation'
    
//     publishDir "${launchDir}/coupling_output", mode: 'copy'

//     input:
//     path estimationScript from "${projectDir}/pipelineScripts/estimateTLcoups.py" 
//     path genesToOne from params.genesToOne
//     tuple path(dataSet), path(graph) from data_and_graphs_3pts
    
//     output:
//     path 'interactions*.npy' into interaction_3pts_ch
//     path 'edgeList*.csv' into interaction_3pts_ch_edgeList

//     """
//     python ${estimationScript} --dataPath ${dataSet} --graphPath ${graph} --intOrder 3 --nResamps ${params.bsResamps} --nCores ${params.cores_3pt} --estimationMethod ${params.estimationMethod} --edgeListAlpha ${params.edgeListAlpha} --genesToOne ${genesToOne} --dataDups ${params.dataDups} --boundBool ${params.boundBool}
//     """

// }

// process identifyStates {
//     label 'interactionEstimation'
    
//     publishDir "${launchDir}/coupling_output", mode: 'copy'

//     input:
//     path estimationScript from "${projectDir}/pipelineScripts/estimateTLcoups.py" 
//     path genesToOne from params.genesToOne
//     tuple path(dataSet), path(graph) from data_and_graphs_3pts
    
//     output:
//     path 'interactions*.npy' into interaction_3pts_ch
//     path 'edgeList*.csv' into interaction_3pts_ch_edgeList

//     """
//     python ${estimationScript} --dataPath ${dataSet} --graphPath ${graph} --intOrder 3 --nResamps ${params.bsResamps} --nCores ${params.cores_3pt} --estimationMethod ${params.estimationMethod} --edgeListAlpha ${params.edgeListAlpha} --genesToOne ${genesToOne} --dataDups ${params.dataDups} --boundBool ${params.boundBool}
//     """

// }
























