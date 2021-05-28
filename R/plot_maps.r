#' @title
#' Plot standard maps
#'
#' @description
#' \code{plot_maps} plots a standard set of diagnostic maps
#'
#' @inheritParams plot_variable
#' @inheritParams sample_variable
#' @inheritParams rnaturalearth::ne_countries
#' @inheritParams fit_model

#' @param plot_set integer-vector defining plots to create
#' \describe{
#'   \item{plot_set=1}{Probability of encounter/non-encounter}
#'   \item{plot_set=2}{Log-expected positive catch rate}
#'   \item{plot_set=3}{Log-predicted density (product of encounter probability and positive catch rates)}
#'   \item{plot_set=4}{Log-positive catch rates (rescaled)}
#'   \item{plot_set=5}{Log-predicted density (rescaled)}
#'   \item{plot_set=6}{Spatio-temporal variation in 1st linear predictor (e.g., encounter probability when using a conventional delta-model)}
#'   \item{plot_set=7}{Spatio-temporal variation in 2nd linear predictor (e.g., log-positive catch rates  when using a conventional delta-model)}
#'   \item{plot_set=8}{Linear predictor for encounter probability}
#'   \item{plot_set=9}{Linear predictor for positive catch rates}
#'   \item{plot_set=10}{Coefficient of variation for predicted density (available only if \code{Data_Fn(...,Options=c('SD_site_logdensity'=1,...))}}
#'   \item{plot_set=11}{Covariates that are included in the model for the 1st linear predictor}
#'   \item{plot_set=12}{Covariates that are included in the model for the 2nd linear predictor}
#'   \item{plot_set=13}{Total biomass across all categories (only useful in a multivariate model)}
#'   \item{plot_set=14}{Covariate effects on encounter probability}
#'   \item{plot_set=15}{Covariate effects on positive catch rates}
#'   \item{plot_set=16}{Spatial variation for 1st linear predictor (Omega1)}
#'   \item{plot_set=17}{Spatial variation for 2nd linear predictor (Omega2)}
#'   \item{plot_set=18}{Spatially-varying response for density covariates in 1st linear predictor (Xi1)}
#'   \item{plot_set=19}{Spatially-varying response for density covariates in 2nd linear predictor (Xi2)}
#'   \item{plot_set=20}{Spatially-varying response for catchability covariates in 1st linear predictor (Phi1)}
#'   \item{plot_set=21}{Spatially-varying response for catchability covariates in 2nd linear predictor (Phi2)}
#' }
#' @param Report tagged list of outputs from TMB model via \code{Obj$report()}
#' @param Sdreport Standard deviation outputs from TMB model via \code{sdreport(Obj)}
#' @param plot_value either \code{plot_value="estimate"} (the default), or a user-specified function that is applied to \code{n_samples} samples from the joint predictive distribution, e.g., to visualize the standard error of a variable by specifying \code{plot_value=sd}
#' @param Panel Whether to plot years for a given category (\code{Panel="Category"}) or categories for a given year ((\code{Panel="Year"})  in each panel figure
#' @param MapSizeRatio Default size for each panel
#' @param years_to_plot integer vector, specifying positions of \code{year_labels} for plotting (used to avoid plotting years with no data, etc.)
#' @param projargs a CRS, e.g. "+proj=utm +datum=WGS84 +units=km +zone=3", which is recommended for displaying the entirety of Alaska in a single plot.See \url{https://proj.org/operations/projections/index.html} for a list of projections to pass via \code{projargs}. I often prefer \code{projargs='+proj=natearth +lat_0=0 +units=km'} where argument \code{+lat_0} allows the user to center eastings on a specified latitude.
#' @param country optional list of countries to display, e.g. c("united states of america", "canada"). If maps are generating visual artefacts, please try using argument \code{country} to simplify the polygons used to represent land features.
#' @param ... arguments passed to \code{FishStatsUtils::plot_variable}
#'
#' @return Mat_xt a matrix (rows: modeled knots; column: modeled year) for plotted output of last element of \code{plot_set}
#'

#' @export
plot_maps <-
function( plot_set = 3,
          Obj = NULL,
          PlotDF,
          Sdreport = NULL,
          projargs = '+proj=longlat',
          Panel = "Category",
          year_labels = NULL,
          years_to_plot = NULL,
          category_names = NULL,
          quiet = FALSE,
          working_dir = paste0(getwd(),"/"),
          MapSizeRatio,
          n_cells,
          plot_value = "estimate",
          n_samples = 100,
          Report,
          TmbData,
          zlim = NULL,
          country = NULL,
          sample_fixed = TRUE,
          ...){

  # Local functions
  extract_value = function( Sdreport, Report, Obj, variable_name, plot_value="estimate", n_samples, sample_fixed=TRUE ){
    if( missing(Report) ){
      Report = Obj$report()
    }
    if( is.function(plot_value) ){
      if(missing(Obj)) stop("Must provide `Obj` for `extract_value(.)` in `plot_maps(.)` when specifying a function for argument `plot_value`")
      Var_r = sample_variable( Sdreport=Sdreport, Obj=Obj, variable_name=variable_name, n_samples=n_samples, sample_fixed=sample_fixed )
      Return = apply( Var_r, MARGIN=1:(length(dim(Var_r))-1), FUN=plot_value )
      if( any(dim(Return)!=dim(Report[[variable_name]])) ){
        stop("Check `extract_value(.)` in `plot_maps(.)`")
      }
      dimnames(Return) = dimnames(Report[[variable_name]])
    }else if( plot_value=="estimate" ){
      Return = Report[[variable_name]]
    }else stop("Check input `plot_value` in `plot_maps(.)`")
    return( Return )
    # apply( Var_r, MARGIN=c(2,4), FUN=function(mat){sum(abs(mat)==Inf)})
  }

  # Extract stuff
  if( !is.null(Obj) ){
    if(missing(Report)) Report = Obj$report()
    TmbData = Obj$env$data
  }else{
    if(plot_value!="estimate") stop("Must provide `Obj` to `plot_maps` when using function for `plot_value`")
  }

  # Fill in missing inputs
  if( missing(MapSizeRatio) ){
    MapSizeRatio = c(3, 3)
  }

  # Loop through plots
  Return = NULL
  for(plot_num in plot_set){

    # Extract elements
    Array_xct = NULL
    plot_code <- c("encounter_prob", "pos_catch", "ln_density", "", "", "epsilon_1", "epsilon_2",
      "linear_predictor_1", "linear_predictor_2", "density_CV", "covariates_1", "covariates_2", "total_density",
      "covariate_effects_1", "covariate_effects_2", "omega_1", "omega_2", "xi_1", "xi_2", "phi_1", "phi_2")[plot_num]

    # Extract matrix to plot
    if(plot_num==1){
      # Presence/absence ("Pres")
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting presence/absense maps")
      if("D_xt"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R1_xt")
      if("D_xct"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R1_xct")
      if("D_xcy"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R1_xcy")
      if("D_gcy"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R1_gcy")
      if("D_gct"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R1_gct")
      if(any(c("dhat_ktp","dpred_ktp")%in%names(Report))) stop("Not implemented for SpatialVAM")
      message( "`plot_num=1` doesn't work well when using ObsModel[2]==1, because average area-swept doesn't generally match area of extrapolation-grid cells" )
    }
    if(plot_num==2){
      # Positive values ("Pos")
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting positive catch rate maps")
      if("D_xt"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R2_xt") )
      if("D_xct"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R2_xct") )
      if("D_xcy"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R2_xcy") )
      if("D_gcy"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R2_gcy") )
      if("D_gct"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="R2_gct") )
      if(any(c("dhat_ktp","dpred_ktp")%in%names(Report)))  stop("Not implemented for SpatialVAM")
      message( "`plot_num=2` doesn't work well when using ObsModel[2]==1, because average area-swept doesn't generally match area of extrapolation-grid cells" )
    }
    if(plot_num==3){
      # Density ("Dens")
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting density maps (in log-space)")
      if("D_xt"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="D_xt") )
      if("D_xct"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="D_xct") )
      if("D_xcy"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="D_xcy") )
      if("D_gcy"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="D_gcy") )
      if("D_gct"%in%names(Report)) Array_xct = log( extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="D_gct") )
      if("dhat_ktp" %in% names(Report)) Array_xct = aperm(extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="dhat_ktp")[,,cI],c(1,3,2))
      if("dpred_ktp" %in% names(Report)) Array_xct = aperm(extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="dpred_ktp")[,,cI],c(1,3,2))
    }
    if(plot_num==4){
      # Positive values rescaled ("Pos_Rescaled")
      stop( "`plot_num=4` is deprecated")
    }
    if(plot_num==5){
      # Density rescaled ("Dens_Rescaled")
      stop( "`plot_num=5` is deprecated")
    }
    if(plot_num==6){
      # Epsilon for presence/absence ("Eps_Pres")
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting spatio-temporal effects (Epsilon) in 1st linear predictor")
      if("D_xt"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Epsilon1_st")
      if("D_xct"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Epsilon1_sct")
      if("D_xcy"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Epsilon1_sct")
      if(any(c("D_gcy","D_gct")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Epsilon1_gct")
      if(any(c("dhat_ktp","dpred_ktp")%in%names(Report)))  stop("Not implemented for SpatialVAM")
    }
    if(plot_num==7){
      # Epsilon for positive values ("Eps_Pos")
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting spatio-temporal effects (Epsilon) in 2nd linear predictor")
      if("D_xt"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Epsilon2_st")
      if("D_xct"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Epsilon2_sct")
      if("D_xcy"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Epsilon2_sct")
      if(any(c("D_gcy","D_gct")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Epsilon2_gct")
      if(any(c("dhat_ktp","dpred_ktp")%in%names(Report)))  stop("Not implemented for SpatialVAM")
    }
    if(plot_num==8){
      # Linear predictor for probability of encounter
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting 1st predictor after action of link function")
      if("D_xt"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="P1_xt")
      if("D_xct"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="P1_xct")
      if("D_xcy"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="P1_xcy")
      if(any(c("D_gcy","D_gct")%in%names(Report))) stop("`plot_maps` not implemented for requested plot_num")
      if(any(c("dhat_ktp","dpred_ktp")%in%names(Report)))  stop("Not implemented for SpatialVAM")
    }
    if(plot_num==9){
      # Linear predictor for positive catch rates
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting 2nd predictor after action of link function")
      if("D_xt"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="P2_xt")
      if("D_xct"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="P2_xct")
      if("D_xcy"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Obj=Obj, Report=Report, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="P2_xcy")
      if(any(c("D_gcy","D_gct")%in%names(Report))) stop("`plot_maps` not implemented for requested plot_num")
      if(any(c("dhat_ktp","dpred_ktp")%in%names(Report)))  stop("Not implemented for SpatialVAM")
    }
    if(plot_num==10){
      # Density ("Dens") CV             # Index_xtl
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting density maps")
      if( is.null(Sdreport) ) stop("Must supply 'Sdreport' if 'plot_num=10'")
      if("D_xt"%in%names(Report)){
        if( !("log(Index_xtl)" %in% rownames(TMB::summary.sdreport(Sdreport))) ) stop("Please re-run with Options('SD_site_logdensity'=1,...) to use 'plot_num=10' in 'SpatialDeltaGLMM'")
        Array_xct = array( TMB::summary.sdreport(Sdreport)[which(rownames(TMB::summary.sdreport(Sdreport))=="log(Index_xtl)"),], dim=c(dim(Report$D_xt),ncol(Report$Index_tl),2), dimnames=list(NULL,NULL,NULL,c('Estimate','Std. Error')) )[,,1,'Std. Error']
      }
      if("D_xct"%in%names(Report)){
        if( !("log(Index_xctl)" %in% rownames(TMB::summary.sdreport(Sdreport))) ) stop("Please re-run with Options('SD_site_logdensity'=1,...) to use 'plot_num=10' in 'VAST'")
        Array_xct = array( TMB::summary.sdreport(Sdreport)[which(rownames(TMB::summary.sdreport(Sdreport))=="log(Index_xctl)"),], dim=c(dim(Report$D_xct),dim(Report$Index_ctl)[3],2), dimnames=list(NULL,NULL,NULL,NULL,c('Estimate','Std. Error')) )[,,,1,'Std. Error']
      }
      if("D_xcy"%in%names(Report)){
        if( !("log(Index_xcyl)" %in% rownames(TMB::summary.sdreport(Sdreport))) ) stop("Please re-run with Options('SD_site_logdensity'=1,...) to use 'plot_num=10' in 'VAST'")
        Array_xct = array( TMB::summary.sdreport(Sdreport)[which(rownames(TMB::summary.sdreport(Sdreport))=="log(Index_xcyl)"),], dim=c(dim(Report$D_xcy),dim(Report$Index_cyl)[3],2), dimnames=list(NULL,NULL,NULL,NULL,c('Estimate','Std. Error')) )[,,,1,'Std. Error']
      }
      if(any(c("dhat_ktp","dpred_ktp")%in%names(Report))) stop("'plot_num=10' not implemented for 'SpatialVAM'")
      # Convert to CV
      Array_xct = sqrt( exp(Array_xct^2) - 1 )
      if(any(c("D_gcy","D_gct")%in%names(Report))) stop("`plot_maps` not implemented for requested plot_num")
    }
    if(plot_num==11){
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting covariates for 1st linear predictor")
      if(is.null(TmbData)) stop( "Must provide `TmbData` to plot covariates" )
      #if(!("X_xtp" %in% names(TmbData))) stop( "Can only plot covariates for VAST version >= 2.0.0" )
      if("X_xtp"%in%names(TmbData)) Array_xct = aperm( TmbData$X_xtp, perm=c(1,3,2) )
      if("X_gtp"%in%names(TmbData)) Array_xct = aperm( TmbData$X_gtp, perm=c(1,3,2) )
      if("X_gctp"%in%names(TmbData)) Array_xct = aperm( array(TmbData$X_gctp[,1,,],dim(TmbData$X_gctp)[c(1,3,4)]), perm=c(1,3,2) )
      if("X1_gctp"%in%names(TmbData)) Array_xct = aperm( array(TmbData$X1_gctp[,1,,],dim(TmbData$X1_gctp)[c(1,3,4)]), perm=c(1,3,2) )
      category_names = 1:dim(Array_xct)[2]
    }
    if(plot_num==12){
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting covariates for 2nd linear predictor")
      if(is.null(TmbData)) stop( "Must provide `TmbData` to plot covariates" )
      if("X2_gctp"%in%names(TmbData)) Array_xct = aperm( array(TmbData$X2_gctp[,1,,],dim(TmbData$X2_gctp)[c(1,3,4)]), perm=c(1,3,2) )
      category_names = 1:dim(Array_xct)[2]
    }
    if(plot_num==13){
      # Total density ("Dens")
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting total density")
      if("D_xt"%in%names(Report)) Array_xct = log(Report$D_xt)
      if("D_xct"%in%names(Report)) Array_xct = log(apply(Report$D_xct, FUN=sum, MARGIN=c(1,3)))
      if("D_xcy"%in%names(Report)) Array_xct = log(apply(Report$D_xcy, FUN=sum, MARGIN=c(1,3)))
      if("D_gcy"%in%names(Report)) Array_xct = log(apply(Report$D_gcy, FUN=sum, MARGIN=c(1,3)))
      if("D_gct"%in%names(Report)) Array_xct = log(apply(Report$D_gct, FUN=sum, MARGIN=c(1,3)))
      logsum = function(vec){ max(vec) + log(sum(exp(vec-max(vec)))) }
      if("dhat_ktp" %in% names(Report)) Array_xct = apply(aperm(Report$dhat_ktp,c(1,3,2)), FUN=logsum, MARGIN=c(1,3))
      if("dpred_ktp" %in% names(Report)) Array_xct = apply(aperm(Report$dpred_ktp,c(1,3,2)), FUN=logsum, MARGIN=c(1,3))
    }
    if(plot_num==14){
      # Covariate effects for probability of encounter
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting covariate effects for 1st linear predictor")
      if("D_xt"%in%names(Report)) stop()
      if("D_xct"%in%names(Report)) stop()
      if("D_xcy"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="eta1_xct")
      if(any(c("D_gcy","D_gct")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="eta1_gct")
      if("dhat_ktp" %in% names(Report)) stop()
      if("dpred_ktp" %in% names(Report)) stop()
    }
    if(plot_num==15){
      # Covariate effects for positive catch rates
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": Plotting covariate effects for 2nd linear predictor")
      if("D_xt"%in%names(Report)) stop()
      if("D_xct"%in%names(Report)) stop()
      if("D_xcy"%in%names(Report)) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="eta2_xct")
      if(any(c("D_gcy","D_gct")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="eta2_gct")
      if("dhat_ktp" %in% names(Report)) stop()
      if("dpred_ktp" %in% names(Report)) stop()
    }
    if(plot_num==16){
      # Spatial effects for probability of encounter
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": plotting spatial effects (Omega) for 1st linear predictor")
      if("D_xt"%in%names(Report)) stop()
      if("D_xct"%in%names(Report)) stop()
      if("D_xcy"%in%names(Report)) Array_xct = Report$Omega1_sc %o% 1
      if(any(c("D_gcy","D_gct")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Omega1_gc") %o% 1
      if("dhat_ktp" %in% names(Report)) stop()
      if("dpred_ktp" %in% names(Report)) stop()
    }
    if(plot_num==17){
      # Spatial effects for positive catch rates
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": plotting spatial effects (Omega) for 2nd linear predictor")
      if("D_xt"%in%names(Report)) stop()
      if("D_xct"%in%names(Report)) stop()
      if("D_xcy"%in%names(Report)) Array_xct = Report$Omega2_sc %o% 1
      if(any(c("D_gcy","D_gct")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Omega2_gc") %o% 1
      if("dhat_ktp" %in% names(Report)) stop()
      if("dpred_ktp" %in% names(Report)) stop()
    }
    if(plot_num==18){
      # Spatially-varying response for density covariates in 1st linear predictor
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": plotting spatially-varying response to density covariates (Xi) for 1st linear predictor")
      if("D_xt"%in%names(Report)) stop()
      if("D_xct"%in%names(Report)) stop()
      if("D_xcy"%in%names(Report)) stop()
      if(any(c("D_gcy","D_gct")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Xi1_gcp")
      if("dhat_ktp" %in% names(Report)) stop()
      if("dpred_ktp" %in% names(Report)) stop()
    }
    if(plot_num==19){
      # Spatially-varying response for density covariates in 1st linear predictor
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": plotting spatially-varying response to density covariates (Xi) for 2nd linear predictor")
      if("D_xt"%in%names(Report)) stop()
      if("D_xct"%in%names(Report)) stop()
      if("D_xcy"%in%names(Report)) stop()
      if(any(c("D_gcy","D_gct")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Xi2_gcp")
      if("dhat_ktp" %in% names(Report)) stop()
      if("dpred_ktp" %in% names(Report)) stop()
    }
    if(plot_num==20){
      # Spatially-varying response for catchability covariates in 1st linear predictor
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": plotting spatially-varying response to catchability covariates (Phi) for 1st linear predictor")
      if("D_xt"%in%names(Report)) stop()
      if("D_xct"%in%names(Report)) stop()
      if("D_xcy"%in%names(Report)) stop()
      if(any(c("Phi1_gk")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Phi1_gk")
      #if(any(c("D_gcy","D_gct")%in%names(Report))) stop("not yet implemented")
      if("dhat_ktp" %in% names(Report)) stop()
      if("dpred_ktp" %in% names(Report)) stop()
      Array_xct = aperm( Array_xct %o% 1, c(1,3,2) )
    }
    if(plot_num==21){
      # Spatially-varying response for catchability covariates in 1st linear predictor
      if( quiet==FALSE ) message(" # plot_num ",plot_num,": plotting spatially-varying response to catchability covariates (Phi) for 2nd linear predictor")
      if("D_xt"%in%names(Report)) stop()
      if("D_xct"%in%names(Report)) stop()
      if("D_xcy"%in%names(Report)) stop()
      if(any(c("Phi2_gk")%in%names(Report))) Array_xct = extract_value(Sdreport=Sdreport, Report=Report, Obj=Obj, plot_value=plot_value, sample_fixed=sample_fixed, n_samples=n_samples, variable_name="Phi2_gk")
      #if(any(c("D_gcy","D_gct")%in%names(Report))) stop("not yet implemented")
      if("dhat_ktp" %in% names(Report)) stop()
      if("dpred_ktp" %in% names(Report)) stop()
      Array_xct = aperm( Array_xct %o% 1, c(1,3,2) )
    }

    # Check for issues
    if( is.null(Array_xct)) stop("Problem with `plot_num` in `plot_maps(.)")
    Bad_xct = ifelse( is.na(Array_xct), FALSE, abs(Array_xct)==Inf )
    if( any(Bad_xct) ) stop("plot_maps(.) has some element of output that is Inf or -Inf, please check results")
    if( !all(years_to_plot %in% 1:dim(Array_xct)[3]) ){
      years_to_plot = 1:dim(Array_xct)[3]
    }

    # Get defaults
    Ncategories = dim(Array_xct)[2]
    Nyears = dim(Array_xct)[3]
    if( is.null(years_to_plot) ) years_to_plot = 1:(dim(Array_xct)[3])
    if( is.null(year_labels) ) year_labels = dimnames(Array_xct)[[3]]
    if( is.null(year_labels) ) year_labels = paste0( "Time_", 1:dim(Array_xct)[3] )
    if( is.null(category_names) ) category_names = dimnames(Array_xct)[[2]]
    if( is.null(category_names) ) category_names = paste0( "Category_", 1:dim(Array_xct)[2] )

    # Plot for each category
    if( tolower(Panel)=="category" ){
      if(length(dim(Array_xct))==2) Nplot = 1
      if(length(dim(Array_xct))==3) Nplot = dim(Array_xct)[2]
      for( cI in 1:Nplot){
        if(length(dim(Array_xct))==2) Return = Mat_xt = Array_xct
        if(length(dim(Array_xct))==3) Return = Mat_xt = array(as.vector(Array_xct[,cI,]),dim=dim(Array_xct)[c(1,3)])
        if( ncol(Mat_xt[,years_to_plot,drop=FALSE]) == length(year_labels[years_to_plot]) ){
          panel_labels = year_labels[years_to_plot]
        }else{
          panel_labels = rep("", ncol(Mat_xt[,years_to_plot,drop=FALSE]))
        }

        file_name = paste0(plot_code, ifelse(Nplot>1, paste0("--",category_names[cI]), ""), ifelse(is.function(plot_value),"-transformed","-predicted") )
        plot_args = plot_variable( Y_gt=Mat_xt[,years_to_plot,drop=FALSE],
          map_list=list("PlotDF"=PlotDF, "MapSizeRatio"=MapSizeRatio), projargs=projargs, working_dir=working_dir,
          panel_labels=panel_labels, file_name=file_name, n_cells=n_cells, zlim=zlim, country=country, ... )
      }
    }
    # Plot for each year
    if( tolower(Panel)=="year" ){
      Nplot = length(years_to_plot)
      for( tI in 1:Nplot){
        if(length(dim(Array_xct))==2) Mat_xc = Array_xct[,years_to_plot[tI],drop=TRUE]
        if(length(dim(Array_xct))==3) Mat_xc = Array_xct[,,years_to_plot[tI],drop=TRUE]
        Return = Mat_xc = array( as.vector(Mat_xc), dim=c(dim(Array_xct)[1],Ncategories)) # Reformat to make sure it has same format for everything

        # Do plot
        file_name = paste0(plot_code, ifelse(Nplot>1, paste0("--",year_labels[years_to_plot][tI]), ""), ifelse(is.function(plot_value),"-transformed","-predicted") )
        plot_args = plot_variable( Y_gt=Mat_xc, map_list=list("PlotDF"=PlotDF, "MapSizeRatio"=MapSizeRatio),
          projargs=projargs, working_dir=working_dir,
          panel_labels=category_names, file_name=file_name, n_cells=n_cells, zlim=zlim, country=country, ... )
      }
    }
  }
  if( is.null(Return) & quiet==FALSE ) message(" # No plots selected in `plot_set`")

  return( invisible(Return) )
}
