# Median absolute deviation-based automatic filters for flowCore objects
#
# This function is meant to create conservative, MAD-based filters for n-peaked
# cytometry variables. The function is so far not flowCore-compliant, and thus
# not available as a direct user function, but only used internally. This
# will change soon.
# @param flowObj The fcs object to be filtered. Both flowFrames and flowSets
# are accepted.
# @param gateVar The variable that should be used to set the gate. Can either
# be an integer or a string.
# @param nMads The number of median absolute deviations that should be
# included. These are calculated separately from each half of the peak, so
# if applied on both sides, there can still be an assymetry present.
# @param filterName The common name to the filter(s) created by the function.
# Default is the name of the gate variable.
# @param nGates The number of gates that should be produced
# @param madSide Which side of the peak(s) should the MAD filter be applied to?
# "low", "high", "both" and "none" supported.
# @param nonMadFilter What filter should be applied on the possible non-mad
# side? The three alternatives are:
# \describe{
#    \item{"deflection"}{Here, the gate is extended to the deflection point
#    marking the start of the next peak.} "none" and "default".
#    \item{"none"}{Here, all events are included}
# }
# It is worth noting that madSide overrides this argument.
# @param adjust The value deciding the accuracy of the density calculation. The
# higher the value, the lower the sensitivity for small aberrations in the
# density.
# @param returnSepFilter Should the gate be returned as a separate object?
# Currently, this defaults to FALSE. Incompatible with returnGateVals = TRUE.
# @param returnGateVals Should only the gate value(s) be returned? Currently, this
# defaults to FALSE. Incompatible with returnSepFilter = TRUE.
# @return If returnSepFilter and returnGateVals are both FALSE, flowObject of
# the same class as flowObj with the gates added as boolean variables to the
# exprs portions of the flowFrames. Otherwise, either a matrix containing the
# information on which cells that belong to whcih gate, or just a vector
# of gate values.
madFilter <- function(flowObj, gateVar = 1, nMads = 2, filterName = "default",
                      nGates = 1, madSide = "both", adjust = 2,
                      nonMadFilter = "deflection", returnSepFilter = FALSE,
                      returnGateVals = FALSE ) {
    # First, the gateVar is converted to an integer, if specified as a string

    if (madSide == "none" && nonMadFilter == "none") {
        stop("With these settings, no filtering would be achieved")
    }

    if (nGates > 1 && madSide != "both" && nonMadFilter == "none") {
        stop("The combination of multiple gates with no nonMadFilter would lead
             to overlapping gates")
    }

    if (returnSepFilter && returnGateVals){
        stop("Either the gate value or the result of applying this value",
             " is returned, not both")
    }

    if (is.character(gateVar)) {
        gateVar <- which(BiocGenerics::colnames(flowObj) == gateVar)
    }

    if (filterName == "default") {
        filterName <- paste0(
            BiocGenerics::colnames(flowObj)[gateVar],
            "_auto_filter"
        )
    }

    if (inherits(flowObj, "flowSet")) {
        resultObj <- fsApply(flowObj, madFilterCoFunction,
            gateVar = gateVar, nMads = nMads,
            filterName = filterName,
            nGates = nGates, madSide = madSide,
            nonMadFilter = nonMadFilter,
            adjust = adjust,
            returnSepFilter = returnSepFilter,
            returnGateVals = returnGateVals
        )
    } else if (inherits(flowObj, "flowFrame")) {
        resultObj <- madFilterCoFunction(flowObj,
            gateVar = gateVar,
            nMads = nMads,
            filterName = filterName,
            nGates = nGates, madSide = madSide,
            nonMadFilter = nonMadFilter,
            adjust = adjust,
            returnSepFilter = returnSepFilter,
            returnGateVals = returnGateVals
        )
    } else {
        stop("The flowObj needs to be either a flowSet or a flowFrame")
    }

    return(resultObj)
}

madFilterCoFunction <- function(focusFrame, gateVar, nMads,
                                filterName, nGates,
                                madSide, nonMadFilter,
                                adjust, returnSepFilter, returnGateVals) {
    focusVar <- exprs(focusFrame[, gateVar])[, 1]

    peakPlaces <- peakIdenti(focusVar,
        nPeaks = nGates,
        adjust = adjust, returnStats = TRUE
    )

    lowMads <- as.list(rep(NA, length = length(peakPlaces[[1]])))
    highMads <- lowMads

    if (madSide == "both" || madSide == "low") {
        lowMads <- lapply(seq_along(peakPlaces[[1]]), function(x)
            peakPlaces[[1]][x] - (
                peakMadCalc(focusVar[which(focusVar >= peakPlaces[[2]][[x]][1] &
                    focusVar < peakPlaces[[1]][x])],
                peakVal = peakPlaces[[1]][x]
                ) * nMads))
    }
    if (madSide == "both" || madSide == "high") {
        highMads <- lapply(seq_along(peakPlaces[[1]]), function(x)
            peakPlaces[[1]][x] + (
                peakMadCalc(focusVar[which(focusVar >= peakPlaces[[1]][x] &
                    focusVar <
                        peakPlaces[[2]][[x]][2])],
                peakVal = peakPlaces[[1]][x]
                ) * nMads))
    }

    # And now, the gates are created, according to the settings above.


    gateValList <- lapply(seq_along(peakPlaces[[1]]), function(x)
        madGateValsCreation(
            focusVar = focusVar, lowMad = lowMads[[x]],
            highMad = highMads[[x]], lowPeakEnd = peakPlaces[[2]][[x]][1],
            highPeakEnd = peakPlaces[[2]][[x]][2], madSide = madSide,
            nonMadFilter = nonMadFilter
        ))
    #And this list is exported, if the interest lies mainly in the gate values
    #and not in transforming the whole dataset
    if (returnGateVals) {
        return(gateValList)
    }
    #If we are interested in getting the actual information about the cells,
    #we get that information here.
    gateVecList <- lapply(seq_along(peakPlaces[[1]]), function(x){
        locVec <- rep(0, times = length(focusVar))
        locVec[which(focusVar >= gateValList[[x]][1] &
                         focusVar < gateValList[[x]][2])] <- 1
        locVec
    }
    )

    if (length(peakPlaces[[1]]) > 1) {
        gateVecMat <- do.call("cbind", gateVecList)

        colnames(gateVecMat) <-
            paste0(filterName, "_", seq_along(peakPlaces[[1]]))
    } else {
        gateVecMat <- matrix(unlist(gateVecList))
        colnames(gateVecMat) <- filterName
    }

    #Here, we export if we do not want the data to be integrated into the
    #flowset
    if (returnSepFilter) {
        return(gateVecMat)
    }
    #If we do want the data to be integrated in the flowSet, here is the place
    #to do so
    focusFrame <- appendFFCols(focusFrame, gateVecMat)
}

peakMadCalc <- function(focusHalfPeak, peakVal) {
    focusHalfPeakCent <- focusHalfPeak - peakVal
    focusPeak <- c(focusHalfPeakCent, focusHalfPeakCent * -1)

    return(mad(focusPeak))
}

#madVecCreation <- function(focusVar, lowMad, highMad, lowPeakEnd,
#                           highPeakEnd, madSide, nonMadFilter) {
#    resultVar <- rep(0, times = length(focusVar))
#    if (madSide == "both") {
#        resultVar[which(focusVar >= lowMad & focusVar < highMad)] <- 1
#    } else if (nonMadFilter == "deflection") {
#        if (madSide == "low") {
#            resultVar[which(focusVar >= lowMad & focusVar < highPeakEnd)] <- 1
#        } else if (madSide == "high") {
#            resultVar[which(focusVar >= lowPeakEnd & focusVar < highMad)] <- 1
#        } else {
#            resultVar[which(focusVar >= lowPeakEnd & focusVar < highPeakEnd)] <-
#                1
#        }
#    } else {
#        if (madSide == "low") {
#            resultVar[which(focusVar >= lowMad)] <- 1
#        } else if (madSide == "high") {
#            resultVar[which(focusVar < highMad)] <- 1
#        }
#    }
#    return(resultVar)
#}

madGateValsCreation <- function(focusVar, lowMad, highMad, lowPeakEnd,
                           highPeakEnd, madSide, nonMadFilter) {
    if (madSide == "both") {
        c(lowMad,highMad)
    } else if (nonMadFilter == "deflection") {
        if (madSide == "low") {
            c(lowMad,highPeakEnd)
        } else if (madSide == "high") {
            c(lowPeakEnd,highMad)
        } else {
            c(lowPeakEnd,highPeakEnd)
        }
    } else {
        if (madSide == "low") {
            c(lowMad,max(focusVar))
        } else if (madSide == "high") {
            c(min(focusVar),highMad)
        }
    }
}

