#include "PythonScript.h"

static int PythonScript::pyinit=0;

PythonScript::PythonScript(){
	// if this is the first python script, Initialise Python
	if(pyinit==0) Py_Initialize();
	pyinit++;
}

PythonScript::~PythonScript(){
	// if this is the last PythonScript wrapper, Finalise python
	--pyinit;
	if(pyinit==0) Py_Finalize();
}

bool PythonScript::Initialise(std::string configfile, DataModel &data){
	
	m_data= &data;
	
	//load config file
	if(configfile!="") m_variables.Initialise(configfile);
	//m_variables.Print();
	
	// get the name of the pythonscript to invoke (excluding directory and '.py' extension)
	// it should be located in one of the directories listed in $PYTHONPATH
	m_variables.Get("PythonScript",pythonscript);
	
	// Load the python script/module
	pName = PyUnicode_FromString(pythonscript.c_str());
	pModule = PyImport_Import(pName);
	
	// we're done with this PyObject; remove reference to trigger cleanup
	Py_DECREF(pName);
	
	//load the standard python fuctions expected to be provided by the python script
	if (pModule != NULL) {
		
		pFuncT = PyObject_GetAttrString(pModule, "SetToolChainVars");
		pFuncI = PyObject_GetAttrString(pModule, "Initialise");
		pFuncE = PyObject_GetAttrString(pModule, "Execute");
		pFuncF = PyObject_GetAttrString(pModule, "Finalise");
		
		if (pFuncT && PyCallable_Check(pFuncT) &&
		    pFuncI && PyCallable_Check(pFuncI) &&
		    pFuncE && PyCallable_Check(pFuncE) &&
		    pFuncF && PyCallable_Check(pFuncF) ){
			
			// The SetToolChainVars python method takes handles to a few standard c++ variables
			// (m_data, m_variables, m_log) and passes them to the python script.
			// This is needed to bootstrap a means of transferring data between c++ and python.
			// first get the pointers to the c++ variables
			intptr_t ptrs[] = {reinterpret_cast<intptr_t>(m_data),
			                   reinterpret_cast<intptr_t>(&m_variables),
			                   reinterpret_cast<intptr_t>(m_data->Log)};
			
			// combine them into a Python tuple
			pArgs = PyTuple_New(3);
			for(unsigned int i=0; i<3; ++i){
				
				intptr_t aptr = ptrs[i];
				// convert intptr_t into a suitable PyObject
				pValue = PyLong_FromLong(aptr);
				if (!pValue) {
					Py_DECREF(pArgs);
					Py_DECREF(pFuncT);
					Py_DECREF(pFuncI);
					Py_DECREF(pFuncE);
					Py_DECREF(pFuncF);
					Py_DECREF(pModule);
					fprintf(stderr, "Cannot convert tuple argument %d for python script %s\n",
					        i,pythonscript.c_str());
					return false;
				}
				
				// Add to the tuple; pValue reference stolen here so don't DECREF it
				int err = PyTuple_SetItem(pArgs, i, pValue);
				if(err){
					Py_DECREF(pArgs);
					Py_DECREF(pFuncT);
					Py_DECREF(pFuncI);
					Py_DECREF(pFuncE);
					Py_DECREF(pFuncF);
					Py_DECREF(pModule);
					fprintf(stderr, "Error %d inserting element %d into variables tuple for python script %s\n",
					        err,i,pythonscript.c_str());
					return false;
				}
				
			}
			
			// invoke SetToolChainVars to import these items into the python environment
			pValue = PyObject_CallObject(pFuncT, pArgs);
			
			// always clean up args after running
			Py_DECREF(pArgs);
			
			// check call return for errors
			if(pValue != NULL){
				
				// function call succeeded, check return value
				if(!(PyLong_AsLong(pValue))){
					// bad return value
					Py_DECREF(pFuncT);
					Py_DECREF(pFuncI);
					Py_DECREF(pFuncE);
					Py_DECREF(pFuncF);
					Py_DECREF(pModule);
					PyErr_Print();
					fprintf(stderr,"Error in SetToolChainVars for python script %s\n",pythonscript.c_str());
					return false;
				}
				
				// otherwise method succeeded
				// clean up handle to return value
				Py_DECREF(pValue);
				// and we're done with this method; clean up handle to the method
				Py_DECREF(pFuncT);
				
			} else {
				// something went wrong with function call
				Py_DECREF(pFuncT);
				Py_DECREF(pFuncI);
				Py_DECREF(pFuncE);
				Py_DECREF(pFuncF);
				Py_DECREF(pModule);
				PyErr_Print();
				fprintf(stderr,"Error invoking SetToolChainVars for python script %s\n",pythonscript.c_str());
				return false;
			}
			
			// ========================
			
			// Same process to invoke a python method again,
			// this time calling the user's Initialise function
			// (takes no arguments)
			pArgs = PyTuple_New(0);
			pValue = PyObject_CallObject(pFuncI, pArgs);
			Py_DECREF(pArgs);
			
			if(pValue != NULL){
				if(!(PyLong_AsLong(pValue))){
					Py_DECREF(pFuncT);
					Py_DECREF(pFuncI);
					Py_DECREF(pFuncE);
					Py_DECREF(pFuncF);
					Py_DECREF(pModule);
					PyErr_Print();
					fprintf(stderr,"Error in Initialise python script %s\n",
					        pythonscript.c_str());
					return false;
				}
				Py_DECREF(pValue);
				Py_DECREF(pFuncI);
			} else {
				Py_DECREF(pFuncI);
				Py_DECREF(pFuncE);
				Py_DECREF(pFuncF);
				Py_DECREF(pModule);
				PyErr_Print();
				fprintf(stderr,"Error invoking Initialise for python script %s\n",pythonscript.c_str());
				return false;
			}
			
		} else {
			// one of the standard methods not available or callable
			if(PyErr_Occurred()) PyErr_Print(); // print python error info if available
			fprintf(stderr, "Cannot find Inialise/Execute/Finalise methods for script %s\n",
			        pythonscript.c_str());
			// cleanup handles for any functions, using XDECREF as they may be null
			Py_XDECREF(pFuncI);
			Py_XDECREF(pFuncT);
			Py_XDECREF(pFuncE);
			Py_XDECREF(pFuncF);
			Py_DECREF(pModule);
		}
		
	} else {
		
		// failed to find script
		PyErr_Print();
		fprintf(stderr, "Failed to load python script %s\n",pythonscript.c_str());
		return false;
		
	}
	
	return true;
}


bool PythonScript::Execute(){
	
	if (pModule != NULL) {
		if (pFuncE && PyCallable_Check(pFuncE)) {
			
			// dummy argument tuple; Execute function takes no args
			pArgs = PyTuple_New(0);
			
			// call the function
			pValue = PyObject_CallObject(pFuncE, pArgs);
			// cleanup dummy args tuple
			Py_DECREF(pArgs);
			
			// check return value
			if(pValue != NULL){
				if (!(PyLong_AsLong(pValue))){
					fprintf(stderr,"Error in Execute for python script %s\n",pythonscript.c_str());
					// this is usually recoverable, so do not unload the module
					return false;
				}
				Py_DECREF(pValue);
			}
			else {
				// error invoking Execute is more serious
				if (PyErr_Occurred()) PyErr_Print();
				Py_DECREF(pFuncE);
				Py_DECREF(pFuncF);
				Py_DECREF(pModule);
				PyErr_Print();
				fprintf(stderr,"Error invoking Execute for python script %s\n",pythonscript.c_str());
				return false;
			}
		} else {
			
			// likewise if Execute is not executable there is a serious problem
			if (PyErr_Occurred()) PyErr_Print();
			fprintf(stderr, "Cannot call Execute for python script %s\n", pythonscript.c_str());
			Py_XDECREF(pFuncE);
			Py_DECREF(pFuncF);
			Py_DECREF(pModule);
			return false;
			
		}
		
	} // else module failed to initialise: bypass
	
	return true;
}


bool PythonScript::Finalise(){
	
	if (pModule != NULL) {
		
		if (pFuncF && PyCallable_Check(pFuncF)) {
			
			// dummy; Finalise function takes no args
			pArgs = PyTuple_New(0);
			
			pValue = PyObject_CallObject(pFuncF, pArgs);
			Py_DECREF(pArgs);
			
			if (pValue != NULL) {
				if (!(PyLong_AsLong(pValue))){
					fprintf(stderr,"Error in Finalise for python script %s\n",pythonscript.c_str());
				}
				Py_DECREF(pValue);
			}
			else {
				PyErr_Print();
				fprintf(stderr,"Error invoking Finalise for python script %s\n",pythonscript.c_str());
			}
			
		} else {
			
			if (PyErr_Occurred()) PyErr_Print();
			fprintf(stderr, "Cannot call Finalise for python script %s\n",pythonscript.c_str());
			
		}
		
		// error or not, we're done with all these function handles now
		Py_XDECREF(pFuncE);
		Py_XDECREF(pFuncF);
		Py_DECREF(pModule);
		
	} // else module failed to initialise: bypass
	
	return true;
}

