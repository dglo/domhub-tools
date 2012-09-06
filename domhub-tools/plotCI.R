plotCI <- function (x, y = NULL, uiw, liw = uiw, aui=NULL, ali=aui,
                    err="y", ylim=NULL, xlim=NULL, sfrac = 0.01, gap=0, add=FALSE,
                    col=par("col"), lwd=par("lwd"), slty=par("lty"), xlab=NULL,
                    ylab=NULL, main="", pt.bg = NA, scol=col,
                    axes=TRUE, ...) {
# from Bill Venables, R-list
  if (is.list(x)) {
    y <- x$y
    x <- x$x
  }
  if (is.null(y)) {
    if (is.null(x))
      stop("both x and y NULL")
    y <- as.numeric(x)
    x <- seq(along = x)
  }
  if (missing(xlab)) xlab <- deparse(substitute(x))
  if (missing(ylab)) ylab <- deparse(substitute(y))
  if (missing(uiw)) { ## absolute limits
    ui <- aui
    li <- ali
  }
  else { ## relative limits
    if (err=="y") z <- y else z <- x
    ui <- z + uiw
    li <- z - liw
  }
  if (err=="y" & is.null(ylim))
    ylim <- range(c(y, ui, li), na.rm=TRUE)
  else
    if (err=="x" & is.null(xlim))
      xlim <- range(c(x, ui, li), na.rm=TRUE)
  if (!add)
    plot(x, y, ylim = ylim, xlim = xlim, col=col, lwd=lwd, xlab=xlab, ylab=ylab,
         main=main, type="n", axes=axes, ...)
  if (gap==TRUE) gap <- 0.01 ## default gap size
  ul <- c(li, ui)
  if (err=="y") {
    ## draw vertical segments
    gap <- rep(gap,length(x))*diff(par("usr")[3:4])
    segments(x , li, x, pmax(y-gap,li), col=scol, lwd=lwd, lty=slty)
    segments(x , ui, x, pmin(y+gap,ui), col=scol, lwd=lwd, lty=slty)
    ## horizontal segments
    x2 <- c(x, x)
    smidge <- diff(par("usr")[1:2]) * sfrac
    segments(x2 - smidge, ul, x2 + smidge, ul, col=scol, lwd=lwd)
  }
  else if (err=="x") {
    ## draw horizontal segments
    gap <- rep(gap,length(x))*diff(par("usr")[1:2])
    segments(li, y, pmax(x-gap,li), y, col=scol, lwd=lwd, lty=slty)
    segments(ui, y, pmin(x+gap,ui), y, col=scol, lwd=lwd, lty=slty)
    ## vertical segments
    y2 <- c(y, y)
    smidge <- diff(par("usr")[3:4]) * sfrac
    segments(ul, y2 - smidge, ul, y2 + smidge, col=scol, lwd=lwd)
  }
  ## _now_ draw the points (in case we want to have "bg" set for points)
  points(x, y, col=col, lwd=lwd, bg=pt.bg, ...)
  invisible(list(x = x, y = y))
}

