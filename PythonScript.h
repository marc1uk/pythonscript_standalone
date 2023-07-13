#ifndef PythonScript_H
#define PythonScript_H

#include <string>
#include <Python.h>
#include "Store.h"
#include "DataModel.h"

class PythonScript {
	
	public:
	
	PythonScript();
	bool Initialise(std::string configfile,DataModel &data);
	bool Execute();
	bool Finalise();
	
	private:
	
	std::string pythonscript;
	Store m_variables;
	PyObject *pName, *pModule, *pFuncT, *pFuncI, *pFuncE, *pFuncF;
	PyObject *pArgs, *pValue;
	static int pyinit;
	
};


#endif
