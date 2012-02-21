#######################################
# OpenMeta[Analyst]                   #
# ----                                #
# diagnostic_methods.r                # 
# Facade module; wraps methods        #
# that perform analysis on diagnostic #
# data in a coherent interface.       # 
#######################################

library(metafor)

diagnostic.logit.metrics <- c("Sens", "Spec", "PPV", "NPV", "Acc")
diagnostic.log.metrics <- c("PLR", "NLR", "DOR")

adjust.raw.data <- function(diagnostic.data, params) {
    # adjust raw data by adding a constant to each entry   
    TP <- diagnostic.data@TP
    FN <- diagnostic.data@FN  
    TN <- diagnostic.data@TN 
    FP <- diagnostic.data@FP
    
    if (params$to == "all") {
        TP <- TP + params$adjust
        FN <- FN + params$adjust
        TN <- TN + params$adjust
        FP <- FP + params$adjust
    } else if (params$to == "only0") {
        product <- TP * FN * TN * FP
        # product equals 0 if at least one entry in a row is 0
        TP[product == 0] <- TP[product == 0] + params$adjust
        FN[product == 0] <- FN[product == 0] + params$adjust
        TN[product == 0] <- TN[product == 0] + params$adjust
        FP[product == 0] <- FP[product == 0] + params$adjust
    } else if (params$to == "if0all") {
        if (any(c(TP,FN,TN,FP) == 0)) {
            TP <- TP + params$adjust
            FN <- FN + params$adjust
            TN <- TN + params$adjust
            FP <- FP + params$adjust    
        }
    }
    data.adj <- list("TP"=TP, "FN"=FN, "TN"=TN, "FP"=FP)
}

compute.diag.point.estimates <- function(diagnostic.data, params) {
    # Computes point estimates based on raw data and adds them to diagnostic.data
    data.adj <- adjust.raw.data(diagnostic.data, params)
    terms <- compute.diagnostic.terms(raw.data=data.adj, params)
    metric <- params$measure    
    TP <- data.adj$TP
    FN <- data.adj$FN  
    TN <- data.adj$TN 
    FP <- data.adj$FP
    
    y <- terms$numerator / terms$denominator
      
    diagnostic.data@y <- eval(call("diagnostic.transform.f", params$measure))$calc.scale(y)
 
    diagnostic.data@SE <- switch(metric,
        Sens <- sqrt((1 / TP) + (1 / FN)), 
        Spec <- sqrt((1 / TN) + (1 / FP)),
        PPV <- sqrt((1 / TP) + (1 / FP)),
        NPV <- sqrt((1 / TN) + (1 / FN)),
        Acc <- sqrt((1 / (TP + TN)) + (1 / (FP + FN))),
        PLR <- sqrt((1 / TP) - (1 / (TP + FN)) + (1 / FP) - (1 / (TN + FP))),
        NLR <- sqrt((1 / TP) - (1 / (TP + FN)) + (1 / FP) - (1 / (TN + FP))),
        DOR <- sqrt((1 / TP) + (1 / FN) + (1 / FP) + (1 / TN)))

    diagnostic.data
}

compute.diagnostic.terms <- function(raw.data, params) { 
    # compute numerator and denominator of diagnostic point estimate.
    metric <- params$measure
    TP <- raw.data$TP
    FN <- raw.data$FN  
    TN <- raw.data$TN 
    FP <- raw.data$FP
    numerator <- switch(metric,
        # sensitivity
        Sens = TP, 
        # specificity
        Spec = TN,
        # pos. predictive value
        PPV =  TP,
        #neg. predictive value
        NPV =  TN,
        # accuracy
        Acc = TP + TN,
        # positive likelihood ratio
        PLR = TP * (TN + FP), 
        # negative likelihood ratio
        NLR = FN * (TN + FP),
        # diagnostic odds ratio
        DOR = TP * TN)
        
    denominator <- switch(metric,
        # sensitivity
        Sens = TP + FN, 
        # specificity
        Spec = TN + FP,
        # pos. predictive value
        PPV =  TP + FP,
        #neg. predictive value
        NPV =  TN + FN,
        # accuracy
        Acc = TP + TN + FP + FN,
        # positive likelihood ratio
        PLR = FP * (TP + FN), 
        # negative likelihood ratio
        NLR = TN * (TP + FN),
        # diagnostic odds ratio
        DOR = FP * FN)  

    terms <- list("numerator"=numerator, "denominator"=denominator)      
}

diagnostic.transform.f <- function(metric.str){
    display.scale <- function(x){
        if (metric.str %in% diagnostic.log.metrics){
            exp(x)
        }
        else {
            if (metric.str %in% diagnostic.logit.metrics){
                invlogit(x)
            }
            else {
                # identity function
                x
            }
        }
    }
    
    calc.scale <- function(x){
        if (metric.str %in% diagnostic.log.metrics){
            log(x)
        }
        else {
        	if (metric.str %in% diagnostic.logit.metrics){
                logit(x)
            }
            else {
                # identity function
                x
            }
         }
    }
    list(display.scale = display.scale, calc.scale = calc.scale)
}

get.res.for.one.diag.study <- function(diagnostic.data, params){
    # this method can be called when there is only one study to 
    # get the point estimate and lower/upper bounds.
    
    ######
    ## Do not check here if the object is NA; we want to recompute the 
    ## data here regardless, and the program will throwup on this check if 
    ## the y estimate doesn't exist on the object.
    #####
    diagnostic.data <- compute.diag.point.estimates(diagnostic.data, params)
    
    y <- diagnostic.data@y
    se <- diagnostic.data@SE

    # note: conf.level is given as, e.g., 95, rather than .95.
    alpha <- 1.0-(params$conf.level/100.0)
    mult <- abs(qnorm(alpha/2.0))
    ub <- y + mult*se
    lb <- y - mult*se
    # we make lists to comply with the get.overall method
    res <- list("b"=c(y), "ci.lb"=lb, "ci.ub"=ub, "se"=se) 
    res
}

logit <- function(x) {
	log(x/(1-x))
}

invlogit <- function(x) {
	exp(x) / (1 + exp(x))
}

###################################################
#     multiple diagnostic methods                 #
###################################################

multiple.diagnostic <- function(fnames, params.list, diagnostic.data) {

    # wrapper for applying multiple diagnostic functions and metrics    

    ####
    # fnames -- names of diagnostic meta-analytic functions to call
    # params.list -- parameter lists to be passed along to the functions in
    #              fnames
    # diagnostic.data -- the (diagnostic data) that is to be analyzed 
    ###
    metrics <- c()
    results <- list()
    pretty.names <- diagnostic.fixed.inv.var.pretty.names()
    sens.spec.outpath <- c()
    for (count in 1:length(params.list)) {
        metrics <- c(metrics, params.list[[count]]$measure)
        if (params.list[[count]]$measure=="Sens") {
            sens.index <- count
            #sens.spec.outpath <- params.list[[count]]$fp_outpath
        }
        if (params.list[[count]]$measure=="Spec") {
            spec.index <- count
            #sens.spec.outpath <- params.list[[count]]$fp_outpath
        }
        if (params.list[[count]]$measure=="PLR") {
            plr.index <- count
            #if (params.list[[count]]$fp_outpath==sens.spec.outpath) {
            # for future use - check that path names are distinct.    
            #    params.list[[count]]$fp_outpath <- paste(sub(".png","",sens.spec.outpath), "1.png", sep="")   
                # if fp_outpath is the same as for sens or spec, append a 1.
            #}
        }
        if (params.list[[count]]$measure=="NLR") {
            nlr.index <- count
            #if (params.list[[count]]$fp_outpath==sens.spec.outpath) {
            #    params.list[[count]]$fp_outpath <- paste(sub(".png","",sens.spec.outpath), "1.png", sep="")   
            #    # if fp_outpath is the same as for sens or spec, append a 1.
            #}
        }
    }
    
    images <- c()
    plot.names <- c()
    plot.params.paths <- c()
    remove.indices <- c()

    if (("Sens" %in% metrics) & ("Spec" %in% metrics)) {
        # create side-by-side forest plots for sens and spec.
       
        params.sens <- params.list[[sens.index]]
        params.spec <- params.list[[spec.index]]
        params.sens$create.plot <- FALSE
        params.spec$create.plot <- FALSE
        params.tmp <- list("left"=params.sens, "right"=params.spec)
        
        fname <- fnames[sens.index]
        diagnostic.data.sens <- compute.diag.point.estimates(diagnostic.data, params.sens)
        diagnostic.data.spec <- compute.diag.point.estimates(diagnostic.data, params.spec)
        diagnostic.data.all <- list("left"=diagnostic.data.sens, "right"=diagnostic.data.spec)
        
        results.sens <- eval(call(fname, diagnostic.data.sens, params.sens))
        results.spec <- eval(call(fname, diagnostic.data.spec, params.spec))
        summary.sens <- list("Summary"=results.sens$Summary)
        names(summary.sens) <- paste(eval(parse(text=paste("pretty.names$measure$", params.sens$measure,sep=""))), " Summary", sep="")
        summary.spec <- list("Summary"=results.spec$Summary)
        names(summary.spec) <- paste(eval(parse(text=paste("pretty.names$measure$", params.spec$measure,sep=""))), " Summary", sep="")
        results <- c(results, summary.sens, summary.spec)
        
        res.sens <- results.sens$Summary$MAResults
        res.spec <- results.spec$Summary$MAResults
        res <- list("left"=res.sens, "right"=res.spec)
        
        plot.data <- create.side.by.side.plot.data(diagnostic.data.all, params=params.tmp, res=res)
        
        forest.path <- paste(params.sens$fp_outpath, sep="")
        two.forest.plots(plot.data, outpath=forest.path)
           
        forest.plot.params.path <- save.data(om.data=diagnostic.data.all, res, params=params.tmp, plot.data)
        plot.params.paths.tmp <- c("Sensitivity and Specificity Forest Plot"=forest.plot.params.path)
        plot.params.paths <- c(plot.params.paths, plot.params.paths.tmp)
               
        images.tmp <- c("Sensitivity and Specificity Forest Plot"=forest.path)
        images <- c(images, images.tmp)
        
        plot.names.tmp <- c("forest plot"="forest.plot")
        plot.names <- c(plot.names, plot.names.tmp)
        
        # create SROC plot
        sroc.path <- "./r_tmp/roc.png"
        png(file=sroc.path, width=5 , height=5, units="in", res=144)
        sroc.plot.data <- create.sroc.plot.data(diagnostic.data, params=params.sens)
        plot.new()
        axis(1, pos=c(0,0))
        axis(2, pos=c(0,0))
        title(xlab="1 - Specificity", ylab="Sensitivity")
        #sroc.plot(sroc.plot.data, outpath=sroc.path)
        subgroup.sroc.plot(sroc.plot.data, color="blue", sym.index=1)
        graphics.off()
        # we use the system time as our unique-enough string to store
        # the params object
        sroc.plot.params.path <- save.plot.data(sroc.plot.data)
        plot.params.paths.tmp <- c("SROC Plot"=sroc.plot.params.path)
        images <- c(images, c("SROC"=sroc.path))
        plot.params.paths <- c(plot.params.paths, plot.params.paths.tmp)
        plot.names <- c(plot.names, c("sroc"="sroc"))
        remove.indices <- c(sens.index, spec.index)
    }
    
    if (("NLR" %in% metrics) & ("PLR" %in% metrics)) {
        # create side-by-side forest plots for NLR and PLR.
        params.nlr <- params.list[[nlr.index]]
        params.plr <- params.list[[plr.index]]
        params.nlr$create.plot <- FALSE
        params.plr$create.plot <- FALSE
        params.tmp <- list("left"=params.nlr, "right"=params.plr)
        
        fname <- fnames[nlr.index]
        diagnostic.data.nlr <- compute.diag.point.estimates(diagnostic.data, params.nlr)
        diagnostic.data.plr <- compute.diag.point.estimates(diagnostic.data, params.plr)
        diagnostic.data.all <- list("left"=diagnostic.data.nlr, "right"=diagnostic.data.plr)
        
        results.nlr <- eval(call(fname, diagnostic.data.nlr, params.nlr))
        results.plr <- eval(call(fname, diagnostic.data.plr, params.plr))
        summary.nlr <- list("Summary"=results.nlr$Summary)
        names(summary.nlr) <- paste(eval(parse(text=paste("pretty.names$measure$", params.nlr$measure,sep=""))), " Summary", sep="")
        summary.plr <- list("Summary"=results.plr$Summary)
        names(summary.plr) <- paste(eval(parse(text=paste("pretty.names$measure$", params.plr$measure,sep=""))), " Summary", sep="")
        results <- c(results, summary.nlr, summary.plr)
        
        res.nlr <- results.nlr$Summary$MAResults
        res.plr <- results.plr$Summary$MAResults
        res <- list("left"=res.nlr, "right"=res.plr)
        
        plot.data <- create.side.by.side.plot.data(diagnostic.data.all, res=res, params.tmp)
        
        forest.path <- paste(params.nlr$fp_outpath, sep="")
        two.forest.plots(plot.data, outpath=forest.path)
           
        forest.plot.params.path <- save.data(diagnostic.data, res, params=params.tmp, plot.data)
        plot.params.paths.tmp <- c("NLR and PLR Forest Plot"=forest.plot.params.path)
        plot.params.paths <- c(plot.params.paths, plot.params.paths.tmp)
               
        images.tmp <- c("NLR and PLR Forest Plot"=forest.path)
        images <- c(images, images.tmp)
        
        plot.names.tmp <- c("forest plot"="forest.plot")
        plot.names <- c(plot.names, plot.names.tmp)
        
        remove.indices <- c(remove.indices, nlr.index, plr.index)
    }

    # remove fnames and params for side-by-side plots
    fnames <- fnames[setdiff(1:length(fnames), remove.indices)]
    params.list <- params.list[setdiff(1:length(params.list), remove.indices)]

    if (length(params.list) > 0) {
        for (count in 1:length(params.list)) {
            # create ma summaries and single (not side-by-side) forest plots.
            #pretty.names <- eval(call(paste(fnames[count],".pretty.names",sep="")))
            results.tmp <- eval(call(fnames[count], diagnostic.data, params.list[[count]]))
            if (is.null(params.list[[count]]$create.plot)) {
               # create plot
              images.tmp <- results.tmp$image
              names(images.tmp) <- paste(eval(parse(text=paste("pretty.names$measure$",params.list[[count]]$measure,sep=""))), " Forest Plot", sep="")
              images <- c(images, images.tmp)
              plot.params.paths.tmp <- results.tmp$plot_params_paths
              names(plot.params.paths.tmp) <- paste(eval(parse(text=paste("pretty.names$measure$", params.list[[count]]$measure,sep=""))), " Forest Plot", sep="")
              plot.params.paths <- c(plot.params.paths, plot.params.paths.tmp)
              plot.names <- c(plot.names, results.tmp$plot_names)
            }
            summary.tmp <- list("Summary"=results.tmp$Summary)
            names(summary.tmp) <- paste(eval(parse(text=paste("pretty.names$measure$",params.list[[count]]$measure,sep=""))), " Summary", sep="")
            results <- c(results, summary.tmp)
        }
    }
    results <- c(results, list("images"=images, "plot_names"=plot.names, 
                               "plot_params_paths"=plot.params.paths))
    #results$images <- images
   # results$plot.names <- plot.names
   # results$plot.params.paths <- plot.params.paths
    results
}

###################################################
#            diagnostic fixed effects             #
###################################################
diagnostic.fixed.inv.var <- function(diagnostic.data, params){
    # assert that the argument is the correct type
    if (!("DiagnosticData" %in% class(diagnostic.data))) stop("Diagnostic data expected.")
    results <- NULL
    if (length(diagnostic.data@TP) == 1 || length(diagnostic.data@y) == 1){
        res <- get.res.for.one.diag.study(diagnostic.data, params)
        # Package res for use by overall method.
        summary.disp <- list("MAResults" = res) 
        results <- list("Summary"=summary.disp)
    } else {
         # call out to the metafor package
        res<-rma.uni(yi=diagnostic.data@y, sei=diagnostic.data@SE, 
                     slab=diagnostic.data@study.names,
                     method="FE", level=params$conf.level,
                     digits=params$digits)
         # Create list to display summary of results
        model.title <- paste("Diagnostic Fixed-effect Model - Inverse Variance (k = ", res$k, ")", sep="")
        data.type <- "diagnostic"
        summary.disp <- create.summary.disp(res, params, model.title, data.type)
        pretty.names <- diagnostic.fixed.inv.var.pretty.names()
        pretty.metric <- eval(parse(text=paste("pretty.names$measure$", params$measure,sep="")))
        for (count in 1:length(summary.disp$table.titles)) {
          summary.disp$table.titles[count] <- paste(pretty.metric, " -", summary.disp$table.titles[count], sep="")
        }
        
        if ((is.null(params$create.plot)) || params$create.plot == TRUE) {
            # A forest plot will be created unless
            # params.create.plot is set to FALSE.
            forest.path <- paste(params$fp_outpath, sep="")
            plot.data <- create.plot.data.diagnostic(diagnostic.data, params, res)
            changed.params <- plot.data$changed.params
            # list of changed params values
            params.changed.in.forest.plot <- forest.plot(forest.data=plot.data, outpath=forest.path)
            changed.params <- c(changed.params, params.changed.in.forest.plot)
            params[names(changed.params)] <- changed.params
            # dump the forest plot params to disk; return path to
            # this .Rdata for later use
            forest.plot.params.path <- save.data(diagnostic.data, res, params, plot.data)
          #
          # Now we package the results in a dictionary (technically, a named
          # vector). In particular, there are two fields that must be returned;
          # a dictionary of images (mapping titles to image paths) and a list of texts
          # (mapping titles to pretty-printed text). In this case we have only one
          # of each.
          #
          plot.params.paths <- c("Forest Plot"=forest.plot.params.path)
          images <- c("Forest Plot"=forest.path)
          plot.names <- c("forest plot"="forest_plot")
          #names(plot.params.paths) <- paste(params$measure, "Forest Plot", sep=" ")
          results <- list("images"=images, "Summary"=summary.disp, 
                          "plot_names"=plot.names, 
                          "plot_params_paths"=plot.params.paths)
       }
        else {
          results <- list("Summary"=summary.disp)
        } 
    }
    results
}

diagnostic.fixed.inv.var.parameters <- function(){
    # parameters
    apply_adjustment_to = c("only0", "all")

    params <- list("conf.level"="float", "digits"="float",
                            "adjust"="float", "to"=apply_adjustment_to)

    # default values
    defaults <- list("conf.level"=95, "digits"=3, "adjust"=.5, "to"="only0")

    var_order = c("conf.level", "digits", "adjust", "to")

    parameters <- list("parameters"=params, "defaults"=defaults, "var_order"=var_order)
}

diagnostic.fixed.inv.var.pretty.names <- function() {
    pretty.names <- list("pretty.name"="Diagnostic Fixed-effect Inverse Variance", 
                         "description" = "Performs fixed-effect meta-analysis with inverse variance weighting.",
                         "conf.level"=list("pretty.name"="Confidence level", "description"="Level at which to compute confidence intervals"), 
                         "digits"=list("pretty.name"="Number of digits", "description"="Number of digits to display in results"),
                         "adjust"=list("pretty.name"="Correction factor", "description"="Constant c that is added to the entries of a two-by-two table."),
                         "to"=list("pretty.name"="Add correction factor to", "description"="When Add correction factor is set to \"only 0\", the correction factor
                                   is added to all cells of each two-by-two table that contains at leason one zero. When set to \"all\", the correction factor
                                   is added to all two-by-two tables if at least one table contains a zero."),
                         "measure"=list("Sens"="Sensitivity", "Spec"="Specificity", "DOR"="Odds Ratio", "PLR"="Positive Likelihood Ratio",
                                        "NLR"="Negative Likelihood Ratio")           
                          )
}

diagnostic.fixed.inv.var.is.feasible <- function(diagnostic.data, metric){
    metric %in% c("Sens", "Spec", "PLR", "NLR", "DOR")
}

diagnostic.fixed.inv.var.overall <- function(results) {
    # this parses out the overall from the computed result
    res <- results$Summary$MAResults
}

################################################
#  diagnostic fixed effects -- mantel haenszel #
################################################
diagnostic.fixed.mh <- function(diagnostic.data, params){
    # assert that the argument is the correct type
    if (!("DiagnosticData" %in% class(diagnostic.data))) stop("Diagnostic data expected.")  
    results <- NULL
    if (length(diagnostic.data@TP) == 1 || length(diagnostic.data@y) == 1){
        res <- get.res.for.one.diagnostic.study(diagnostic.data, params)
         # Package res for use by overall method.
        summary.disp <- list("MAResults" = res) 
        results <- list("Summary"=summary.disp)
    } 
    else {
        res <- switch(params$measure,
        
            "DOR" = rma.mh(ai=diagnostic.data@TP, bi=diagnostic.data@FN, 
                                ci=diagnostic.data@FP, di=diagnostic.data@TN, slab=diagnostic.data@study.names,
                                level=params$conf.level, digits=params$digits, measure="OR",
                                add=c(params$adjust, 0), to=c(as.character(params$to), "none")),
                                
            "PLR" = rma.mh(ai=diagnostic.data@TP, bi=diagnostic.data@FN, 
                                ci=diagnostic.data@FP, di=diagnostic.data@TN, slab=diagnostic.data@study.names,
                                level=params$conf.level, digits=params$digits, measure="RR",
                                add=c(params$adjust, 0), to=c(as.character(params$to), "none")),
        
            "NLR" = rma.mh(ai=diagnostic.data@FN, bi=diagnostic.data@TP, 
                                ci=diagnostic.data@TN, di=diagnostic.data@FP, slab=diagnostic.data@study.names,
                                level=params$conf.level, digits=params$digits, measure="RR",
                                add=c(params$adjust, 0), to=c(as.character(params$to), "none")))
  
            # if measure is "NLR", switch ai with bi, and ci with di
            # in order to use rma.mh with measure "RR"

        #                        
        # Create list to display summary of results
        #
        model.title <- "Diagnostic Fixed-effect Model - Mantel Haenszel"
        data.type <- "diagnostic"
        summary.disp <- create.summary.disp(res, params, model.title, data.type)
        pretty.names <- diagnostic.fixed.mh.pretty.names()
        pretty.metric <- eval(parse(text=paste("pretty.names$measure$", params$measure,sep="")))
        for (count in 1:length(summary.disp$table.titles)) {
          summary.disp$table.titles[count] <- paste(pretty.metric, " -", summary.disp$table.titles[count], sep="")
        }
        #
        # generate forest plot
        #
        if ((is.null(params$create.plot)) || (params$create.plot == TRUE)) {
            if (is.null(diagnostic.data@y) || is.null(diagnostic.data@SE)) {
                diagnostic.data <- compute.diag.point.estimates(diagnostic.data, params)
                # compute point estimates for plot.data in case they are missing
            }
            forest.path <- paste(params$fp_outpath, sep="")
            plot.data <- create.plot.data.diagnostic(diagnostic.data, params, res)
            changed.params <- plot.data$changed.params
            # list of changed params values
            params.changed.in.forest.plot <- forest.plot(forest.data=plot.data, outpath=forest.path)
            changed.params <- c(changed.params, params.changed.in.forest.plot)
            params[names(changed.params)] <- changed.params
            # dump the forest plot params to disk; return path to
            # this .Rdata for later use
            forest.plot.params.path <- save.data(diagnostic.data, res, params, plot.data)
            
            plot.params.paths <- c("Forest Plot"=forest.plot.params.path)
            images <- c("Forest Plot"=forest.path)
            plot.names <- c("forest plot"="forest_plot")
            results <- list("images"=images, "Summary"=summary.disp, 
                            "plot_names"=plot.names, 
                            "plot_params_paths"=plot.params.paths)
        }
        else {
            results <- list("Summary"=summary.disp)
        }    
    }
    results
}
                                
diagnostic.fixed.mh.parameters <- function(){
    # parameters
    apply_adjustment_to = c("only0", "all")
    
    params <- list("conf.level"="float", "digits"="float",
                            "adjust"="float", "to"=apply_adjustment_to)
    
    # default values
    defaults <- list("conf.level"=95, "digits"=3, "adjust"=.5, "to"="only0")
    
    var_order = c("conf.level", "digits", "adjust", "to")
    
    # constraints
    parameters <- list("parameters"=params, "defaults"=defaults, "var_order"=var_order)
}

diagnostic.fixed.mh.pretty.names <- function() {
    pretty.names <- list("pretty.name"="Diagnostic Fixed-effect Mantel Haenszel", 
                         "description" = "Performs fixed-effect meta-analysis using the Mantel Haenszel method.",
                         "conf.level"=list("pretty.name"="Confidence level", "description"="Level at which to compute confidence intervals"), 
                         "digits"=list("pretty.name"="Number of digits", "description"="Number of digits to display in results"),
                         "adjust"=list("pretty.name"="Correction factor", "description"="Constant c that is added to the entries of a two-by-two table."),
                         "to"=list("pretty.name"="Add correction factor to", "description"="When Add correction factor is set to \"only 0\", the correction factor
                                   is added to all cells of each two-by-two table that contains at leason one zero. When set to \"all\", the correction factor
                                   is added to all two-by-two tables if at least one table contains a zero."),
                          "measure"=list("Sens"="Sensitivity", "Spec"="Specificity", "DOR"="Odds Ratio", "PLR"="Positive Likelihood Ratio",
                                        "NLR"="Negative Likelihood Ratio")
                          )
}

diagnostic.fixed.mh.is.feasible <- function(diagnostic.data, metric){
    metric %in% c("DOR", "PLR", "NLR")
}

diagnostic.fixed.mh.overall <- function(results) {
    # this parses out the overall from the computed result
    res <- results$Summary$MAResults
}

##################################
#  diagnostic random effects     #
##################################
diagnostic.random <- function(diagnostic.data, params){
    # assert that the argument is the correct type
    if (!("DiagnosticData" %in% class(diagnostic.data))) stop("Diagnostic data expected.")
    
    results <- NULL
    if (length(diagnostic.data@TP) == 1 || length(diagnostic.data@y) == 1){
        res <- get.res.for.one.diag.study(diagnostic.data, params)
        # Package res for use by overall method.
        summary.disp <- list("MAResults" = res) 
        results <- list("Summary"=summary.disp)
    } else {
        # call out to the metafor package
        res<-rma.uni(yi=diagnostic.data@y, sei=diagnostic.data@SE, 
                 slab=diagnostic.data@study.names,
                 method=params$rm.method, level=params$conf.level,
                 digits=params$digits)
        #                        
        # Create list to display summary of results
        #

        model.title <- paste("Diagnostic Random-Effects Model (k = ", res$k, ")", sep="")
        data.type <- "diagnostic"
        summary.disp <- create.summary.disp(res, params, model.title, data.type)
        pretty.names <- diagnostic.random.pretty.names()
        pretty.metric <- eval(parse(text=paste("pretty.names$measure$", params$measure,sep="")))
        for (count in 1:length(summary.disp$table.titles)) {
          summary.disp$table.titles[count] <- paste(pretty.metric, " -", summary.disp$table.titles[count], sep="")
        }
        #
        # generate forest plot 
        #
        if ((is.null(params$create.plot)) || (params$create.plot == TRUE)) {
            forest.path <- paste(params$fp_outpath, sep="")
            plot.data <- create.plot.data.diagnostic(diagnostic.data, params, res)
            changed.params <- plot.data$changed.params
            # list of changed params values
            params.changed.in.forest.plot <- forest.plot(forest.data=plot.data, outpath=forest.path)
            changed.params <- c(changed.params, params.changed.in.forest.plot)
            params[names(changed.params)] <- changed.params
            # update params values
            # we use the system time as our unique-enough string to store
            # the params object
            forest.plot.params.path <- save.data(diagnostic.data, res, params, plot.data)
            
            plot.params.paths <- c("Forest Plot"=forest.plot.params.path)
            images <- c("Forest Plot"=forest.path)
            plot.names <- c("forest plot"="forest_plot")
            results <- list("images"=images, "Summary"=summary.disp, 
                            "plot_names"=plot.names, 
                            "plot_params_paths"=plot.params.paths)
        }
        else {
            results <- list("Summary"=summary.disp)
        } 
    } 
    results
}

diagnostic.random.parameters <- function(){
    apply.adjustment.to = c("only0", "all")
    rm.method.ls <- c("HE", "DL", "SJ", "ML", "REML", "EB")
    params <- list("rm.method"=rm.method.ls, "conf.level"="float", "digits"="float",
                            "adjust"="float", "to"=apply.adjustment.to)
    
    # default values
    defaults <- list("rm.method"="DL", "conf.level"=95, "digits"=3,  
                            "adjust"=.5, "to"="only0")
    
    var.order <- c("rm.method", "conf.level", "digits", "adjust", "to")
    parameters <- list("parameters"=params, "defaults"=defaults, "var_order"=var.order)
}

diagnostic.random.pretty.names <- function() {
    pretty.names <- list("pretty.name"="Diagnostic Random-Effects", 
                         "description" = "Performs random-effects meta-analysis.",
                         "rm.method"=list("pretty.name"="Random method", "description"="Method for estimating between-studies heterogeneity"),                      
                         "conf.level"=list("pretty.name"="Confidence level", "description"="Level at which to compute confidence intervals"), 
                         "digits"=list("pretty.name"="Number of digits", "description"="Number of digits to display in results"),
                         "adjust"=list("pretty.name"="Correction factor", "description"="Constant c that is added to the entries of a two-by-two table."),
                         "to"=list("pretty.name"="Add correction factor to", "description"="When Add correction factor is set to \"only 0\", the correction factor
                                   is added to all cells of each two-by-two table that contains at leason one zero. When set to \"all\", the correction factor
                                   is added to all two-by-two tables if at least one table contains a zero."),
                         "measure"=list("Sens"="Sensitivity", "Spec"="Specificity", "DOR"="Odds Ratio", "PLR"="Positive Likelihood Ratio",
                                        "NLR"="Negative Likelihood Ratio")
                         )
}

diagnostic.random.is.feasible <- function(diagnostic.data, metric){
    metric %in% c("Sens", "Spec", "PLR", "NLR", "DOR")      
}
diagnostic.random.overall <- function(results) {
    # this parses out the overall from the computed result
    res <- results$Summary$MAResults
}

##################################
#            SROC Plot           #
##################################
create.sroc.plot.data <- function(diagnostic.data, params){
    # create plot data for an ROC plot.
  
    # assert that the argument is the correct type
    if (!("DiagnosticData" %in% class(diagnostic.data))) stop("Diagnostic data expected.")

    # add constant to zero cells
    data.adj <- adjust.raw.data(diagnostic.data,params)
    # compute true positive ratio = sensitivity 
    TPR <- data.adj$TP / (data.adj$TP + data.adj$FN)
    # compute false positive ratio = 1 - specificity
    FPR <- data.adj$FP / (data.adj$TN + data.adj$FP)
    S <- logit(TPR) + logit(FPR)
    D <- logit(TPR) - logit(FPR)
    s.range <- list("max"=max(S), "min"=min(S))
    params$sroc.weighted <- FALSE
    # remove if this is added in the GUI as a parameter.
    
    inv.var <- data.adj$TP + data.adj$FN + data.adj$FP + data.adj$TN
    if (params$sroc.weighted) {
      # weighted linear regression
      res <- lm(D ~ S, weights=inv.var)
    } else {
      # unweighted regression 
      res <- lm(D~S)
    }
    fitted.line <- list(intercept=res$coefficients[1], slope=res$coefficients[2])
    
    plot.options <- list()
    plot.options$roc.xlabel <- params$roc_xlabel
    plot.options$roc.ylabel <- params$roc_ylabel
    plot.options$roc.title <- params$roc_title
    # for future use as options from GUI
    plot.data <- list("fitted.line" = fitted.line, "TPR"=TPR, "FPR"=FPR, "inv.var" = inv.var, "s.range" = s.range, "weighted"=params$sroc.weighted, "plot.options"=plot.options)
}

###################################################
#            create side-by-side forest.plots     #
###################################################

create.side.by.side.plot.data <- function(diagnostic.data, params, res) {    
    # creates data for two side-by-side forest plots
    params.left <- params$left
    params.right <- params$right
    #params.left$fp_show_col1 <- 'TRUE'
    #params.right$fp_show_col1 <- 'FALSE'
    # only show study names on the left plot
    res.left <- res$left
    res.right <- res$right    
    diagnostic.data.left <- diagnostic.data$left
    diagnostic.data.right <- diagnostic.data$right
    
    plot.data.left <- create.plot.data.diagnostic(diagnostic.data.left, params.left, res.left)
    plot.data.left$options$fp.title <- pretty.metric.name(as.character(params.left$measure))
      
    plot.data.right <- create.plot.data.diagnostic(diagnostic.data.right, params.right, res.right)
    plot.data.right$options$fp.title <- pretty.metric.name(as.character(params.right$measure))
    
    plot.data <- list("left"=plot.data.left, "right"=plot.data.right)
    plot.data
}