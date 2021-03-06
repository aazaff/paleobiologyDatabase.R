# This module is still under development, and is not recommended for general use.

# Least inverse squares M Estimator
mestimateMean<-function(MeansVector,ErrorsVector) {
	SquaredErrors<-ErrorsVector^2
	Numerator<-MeansVector/SquaredErrors
	InverseErrors<-sum(1/SquaredErrors)
	Mean<-sum(Numerator)/InverseErrors
	Error<-1/sqrt(InverseErrors)
	return(c(Mean,Error,length(MeansVector)))
	}
