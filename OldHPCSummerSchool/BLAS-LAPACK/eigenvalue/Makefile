PROGRAM = eigenvalue
PROGSRC = eigenvalue.cc print_mat.cc
CXXFLAGS = -g -std=c++0x
#CXXLIBS = -L/home/crawdad/lib -llapack0 -lblas0 -lgfortran
#CXXLIBS = -L/home/crawdad/lib -llapack3 -lblas3 -lgfortran
#CXXLIBS = -L$(ATLAS_LIB) -llapack -lcblas -lf77blas -latlas -lgfortran
CXX = icpc
CXXLIBS = -mkl

OBJECTS = $(PROGSRC:%.cc=%.o)

$(PROGRAM): $(OBJECTS)
	$(CXX) $(CXXFLAGS) $^ $(CXXLIBS) -o $@

%.o: $.cc
	$(CXX) $(CXXFLAGS) -c $<

clean:
	rm -f $(OBJECTS) $(PROGRAM)
