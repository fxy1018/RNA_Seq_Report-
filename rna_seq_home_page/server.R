library(shiny)
library(DT)
library(pool)
library(dplyr)
library(plotly)
library(png)
source('view/report_overview_view.R')
source('view/report_gene_view.R')
source('view/report_pathway_view.R')
source('view/report_more_view.R')
source('getDataTables.R')
source('helpFunctions.R')


# Define server logic required to draw a histogram
shinyServer(function(input, output, session) {

  #render experiment table  
  output$experiment_table <- DT::renderDataTable(
    {experiment_table2}, rownames=FALSE, selection='none')
  
  
  
  observeEvent(input$view_report,{
    
    #get experiment id
    exp_id = experiment_table$id[input$experiment==experiment_table$description]
    
    #get species id
    species_id_input = experiment_table$species_id[input$experiment==experiment_table$description]
    
    #get condition table
    condition_table = getConditionTable(exp_id)
    
    #get sample table
    sample_table = getSampleTable(exp_id, condition_table)
    output$sample_table <- DT::renderDataTable(DT::datatable(sample_table, rownames=FALSE, selection = 'none'))
    
    #get ensembl gene table
    ensembl_gene_table = ensembl %>%
      filter(species_id == species_id_input)
    
    #get diff gene table
    diff_gene_table_all <- getDiffGeneTable(exp_id, condition_table)
    
    #get uniprot table
    uniprot_table <- uniprot %>% filter(species_id == species_id_input)

    #################end of getting data####################
    
    #update main page content
    removeUI(
      selector = "#exp_table_col"
    )
    #render report
    insertUI(
      selector = '#col_9',
      ui = tags$div(
        id = "exp_table_col",
        navbarPage(paste0(input$experiment, " Report"), id = "overview",  theme = shinytheme("simplex"),
          report_overview_view(),
          report_gene_view(condition_table),
          report_pathway_view(condition_table),
          report_more_view(condition_table)
        )
      )
    )
    
    ################# gene page #############################
    
    ############gene expression tab#############
    observeEvent(input$gene_condition,{
      updateSelectizeInput(session, "gene_gene", choices = ensembl_gene_table$gene_name, server = TRUE)
    })
    
    observeEvent(input$gene_update,{

      select_gene_condition = input$gene_condition
      select_gene_gene = input$gene_gene
      
      if ("All" %in% select_gene_condition) {
        select_gene_condition = condition_table$name
      }
      
      gene_expression_table = getExpressionGeneTable(condition_table, select_gene_condition, select_gene_gene,exp_id, ensembl_gene_table)
      
      
      output$gene_expression_table <- DT::renderDataTable(
        {
          data = gene_expression_table
        },
        escape = FALSE, rownames = FALSE, selection='none'
      )
      
    })
    
    
    ############end of gene expression tab#############
    
    ########diff gene table########
    output$diff_gene_table <- DT::renderDataTable(
      {
        
        data = filterDiffGeneTable(diff_gene_table_all, condition_table,input$condition1, input$condition2, input$fdr)
        if (input$screted == TRUE){
          data = merge(data, uniprot_table, by.x="gene_name", by.y="entry_name", all.x=TRUE)
          print(head(data))
          data = data[!is.na(data$uniprot), c(-10,-11)]
          data$Uniprot <- createLink(data$uniprot, "Uniprot", species_id_input)
        }
        
        data$NCBI <- createLink(data$entrez, "NCBI", species_id_input)
        data$OMIM <- createLink(data$entrez, "OMIM", species_id_input)
        
        data
      },
      escape = FALSE, rownames = FALSE, selection='none'
    )
    
    #download diff gene table
    output$downloadDiffGeneTable <- downloadHandler(
      filename = function(){
        paste0("genetable_", Sys.Date(), '.csv')
      },
      content = function(file){
        data = filterDiffGeneTable(diff_gene_table_all, condition_table,input$condition1, input$condition2, input$fdr)
        if (input$screted == TRUE){
          data = merge(data, uniprot_table, by.x="gene_name", by.y="entry_name", all.x=TRUE)
          data = data[!is.na(data$uniprot), ]
        }
        write.csv(data, file, quote = F, row.names = F)
      }
    )
    
    #volcano plot of diff gene page
    output$volcanoPlot <-renderPlotly({
      s = input$geneTable_rows_selected
      data = filterDiffGeneTable(diff_gene_table_all, condition_table,input$condition1, input$condition2, input$fdr)
      data$comparison = paste(data$condition1, data$condition2, sep="_vs_")
      if (input$screted == TRUE){
        data = merge(data, uniprot_table, by.x="gene_name", by.y="entry_name", all.x=TRUE)
        data = data[!is.na(data$uniprot), ]
      }
      
      data$logfdr = log(as.numeric(data$fdr))
      
      s_point <- data[s,]
      
      dot_plot <- function(dat){
        plot_ly(dat, x=~logfc, y=~logfdr, text=~paste("Gene:", gene_name), name = dat$comparison[1]) %>%
          layout(yaxis=list(autorange="reversed"),xaxis=list(title="logFC"), yaxis=list(title="logFDR"))
        # %>%
        # add_trace(x=~s_point$logFC, y=~s_point$logFDR, type="scatter", col="red")
      }
      
      data %>%
        group_by(comparison) %>%
        do(map=dot_plot(.)) %>%
        subplot(nrows=2, margin=0.05, titleX=T, titleY=T) %>%
        layout(title = paste0("volcano plot of ", input$experiment))
    })
    
    ######################end of gene page########################
    ######################pathway page############################
    #####KEGG Tab######
    #get kegg table
    kegg_table_all <- getKEGGTable(exp_id, condition_table)
    
    output$kegg_table <- DT::renderDataTable(
      DT::datatable({
        data = filterKEGGTable(kegg_table_all, condition_table, input$keggcondition1, input$keggcondition2, input$kegg_fdr)
        data
      }, escape=FALSE, selection='single'))
    
    
    output$downloadKeggTable <- downloadHandler(
      filename = function(){
        paste("kegg-pathway-table-", Sys.Date(), '.csv', sep='')
      },
      content = function(file){
        data <- filterKEGGTable(kegg_table_all, condition_table, input$keggcondition1, input$keggcondition2, input$kegg_fdr)
        
        write.csv(data,file, quote = F, row.names = F)
      }
    )
    
    output$pathview <- renderImage({
      row = input$kegg_table_rows_selected
      validate(
        need(row[1]!=0,"Select a pathway to view the pathway")
      )
      data <- filterKEGGTable(kegg_table_all, condition_table, input$keggcondition1, input$keggcondition2, input$kegg_fdr)
      path = data[row,]
      kegg = path$kegg
      condition1 = path$condition1
      condition2 = path$condition2
      src = getSRC(kegg, condition1, condition2, exp_id, pathview, condition_table)
      
      validate(
        need(length(src)!=0,"This pathway have no pathview, please select another one")
      )

      outfile <- tempfile(fileext = '.png')
      img <- readPNG(src)

      #get size
      h<-dim(img)[1]
      w<-dim(img)[2]

      png(outfile, width=w, height=h)
      par(mar=c(0,0,0,0), xpd=NA, mgp=c(0,0,0), oma=c(0,0,0,0), ann=F)
      plot.new()
      plot.window(0:1, 0:1)

      #fill plot with image
      usr<-par("usr")
      rasterImage(img, usr[1], usr[3], usr[2], usr[4])

      #close image
      dev.off()

      list(src = outfile,
           contentType = 'image/png',
           width = 600,
           height = 400,
           alt = "This is alternate text")

    }, deleteFile = T)
    
    
    output$mappedGene2KEGGTable <- renderDataTable({
      row = input$kegg_table_rows_selected
      validate(
        need(row[1]!=0,"")
      )
      
      data <- filterKEGGTable(kegg_table_all, condition_table, input$keggcondition1, input$keggcondition2, input$kegg_fdr)
      
      path = data[row,]
    
      p_id = path$kegg
      condition1 = path$condition1
      condition2 = path$condition2
  
      genedata <- gene2KEGGTable[gene2KEGGTable$kegg == p_id, ]
      diff_genes <- filterDiffGeneTable(diff_gene_table_all, condition_table,condition1, condition2, 0.05)
      if (input$screted == TRUE){
        diff_genes = merge(diff_genes, uniprot_table, by.x="gene_name", by.y="entry_name", all.x=TRUE)
        diff_genes = diff_genes[!is.na(diff_genes$uniprot), ]
        diff_genes$Uniprot <- createLink(diff_genes$uniprot, "Uniprot", species_id_input)
      }
      
      diff_genes$NCBI <- createLink(diff_genes$entrez, "NCBI", species_id_input)
      diff_genes$OMIM <- createLink(diff_genes$entrez, "OMIM", species_id_input)
   
      genedata <- merge(diff_genes, genedata, by.x = "entrez", by.y = "entrez" , all = FALSE)
      genedata <- genedata[, c(1:8, 13, 9,10)]
      
      return(genedata)
    }, escape=F)
    
    #####KEGG Tab END##########
    
    #####Reactome Tab##########
    #get reactome table 
    reactome_table_all <- getReactomeTable(exp_id, condition_table)
    
    output$reactome_table <- DT::renderDataTable(
      DT::datatable({
        data = filterReactomeTable(reactome_table_all, condition_table, input$reactomecondition1, input$reactomecondition2, input$reactomeFDR)
        data = data[, -dim(data)[2]]
      }, escape=FALSE, selection='single'))
    
    
    output$downloadReactomeTable <- downloadHandler(
      filename = function(){
        paste("reactome-pathway-table-", Sys.Date(), '.csv', sep='')
      },
      content = function(file){
        data = filterReactomeTable(reactome_table_all, condition_table, input$reactomecondition1, input$reactomecondition2, input$reactomeFDR)
        
        write.csv(data,file, quote = F, row.names = F)
      }
    )
    
    output$reactomePage <- renderText({
      row = input$reactome_table_rows_selected
      validate(
        need(row[1]!=0,"Selected a reactome pathway")
      )
      
      data <- filterReactomeTable(reactome_table_all, condition_table, input$reactomecondition1, input$reactomecondition2, input$reactomeFDR)
      path = data[row,]
      p_id = path$reactome
      genes =  path$genes
      genes <- unlist(strsplit(as.character(genes[1]), split="/"))
      out = getReactomeJS(p_id,genes)
      return(out)
    })
    
    output$mappedGene2ReactomeTable <- renderDataTable({
      row = input$reactome_table_rows_selected
      validate(
        need(row[1]!=0,"")
      )
      
      data <- filterReactomeTable(reactome_table_all, condition_table, input$reactomecondition1, input$reactomecondition2, input$reactomeFDR)
      
      path = data[row,]
      
      genes = unlist(strsplit(path$genes, "/"))
      genedata = data.frame(order = c(1:length(genes)), gene = genes)
      condition1 = path$condition1
      condition2 = path$condition2
      
      diff_genes <- filterDiffGeneTable(diff_gene_table_all, condition_table,condition1, condition2, 0.05)
      if (input$screted == TRUE){
        diff_genes = merge(diff_genes, uniprot_table, by.x="gene_name", by.y="entry_name", all.x=TRUE)
        diff_genes = diff_genes[!is.na(diff_genes$uniprot), ]
        diff_genes$Uniprot <- createLink(diff_genes$uniprot, "Uniprot", species_id_input)
      }
      
      diff_genes$NCBI <- createLink(diff_genes$entrez, "NCBI", species_id_input)
      diff_genes$OMIM <- createLink(diff_genes$entrez, "OMIM", species_id_input)
      
    
      genedata <- merge(diff_genes, genedata, by.x = "gene_name", by.y = "gene" , all = FALSE)
      genedata <- genedata[, -dim(genedata)[2]]
      
      return(genedata)
    }, escape=F)
    
    
  })
})