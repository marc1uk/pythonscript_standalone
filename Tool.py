# python Tool script
# ------------------
# import cppyy and ctypes for interaction with c++ entities
import cppyy, cppyy.ll
import ctypes
# streamline accessing std namespace
std = cppyy.gbl.std
# pull in classes from the DataModel
cppyy.add_include_path('include')
cppyy.add_include_path('ToolDAQ/boost_1_66_0/install/include')
cppyy.add_include_path('ToolDAQ/zeromq-4.0.7/include')
cppyy.include('DataModel.h')
cppyy.load_library('libDataModel.so')
from cppyy.gbl import DataModel
from cppyy.gbl import Store
from cppyy.gbl import Logging
# import infrastructure for declaring an abstract base class
from abc import ABC, abstractmethod

class Tool(ABC):
    # base class members
    m_data = None
    m_variables = None
    m_log = None
    
    m_verbosity = 1
    v_error = 0
    v_warning = 1
    v_message = 2
    v_debug = 3
        
    # helper function to bootstrap access to the parent ToolChain
    def SetToolChainVars(self, m_data_in, m_variables_in, m_log_in):
        
        # get datamodel, logger and tool configs
        self.m_data = cppyy.ll.reinterpret_cast['DataModel*'](m_data_in)
        self.m_log = cppyy.ll.reinterpret_cast['Logging*'](m_log_in)
        self.m_variables = cppyy.ll.reinterpret_cast['Store*'](m_variables_in)
        
        # get verbosity from config store
        m_verbosity_ref = ctypes.c_int(1)
        self.m_variables.Get("verbosity",m_verbosity_ref)
        self.m_verbosity = m_verbosity_ref.value
        return 1
    
    @abstractmethod
    def Initialise(self):
        pass
    
    @abstractmethod
    def Execute(self):
        pass

    @abstractmethod
    def Finalise(self):
        pass
