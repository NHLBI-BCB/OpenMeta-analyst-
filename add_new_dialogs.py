from PyQt4.Qt import *
import ui_new_group
import ui_new_follow_up
import ui_new_outcome
import ui_new_covariate

class AddNewGroupForm(QDialog, ui_new_group.Ui_new_group_dialog):
    
    def __init__(self, parent=None):
        super(AddNewGroupForm, self).__init__(parent)
        self.setupUi(self)
        
        
class AddNewFollowUpForm(QDialog, ui_new_follow_up.Ui_new_follow_up_dialog):
    
    def __init__(self, parent=None):
        super(AddNewFollowUpForm, self).__init__(parent)
        self.setupUi(self)
        
        
class AddNewOutcomeForm(QDialog, ui_new_outcome.Ui_Dialog):
    
    def __init__(self, parent=None):
        super(AddNewOutcomeForm, self).__init__(parent)
        self.setupUi(self)
        self._populate_combo_box()

        
    def _populate_combo_box(self):
        for name, type_id in zip([QString(s) for s in ["Binary", "Continuous", "Diagnostic", "Other"]],
                                     [QVariant(i) for i in range(4)]):
            self.datatype_cbo_box.addItem(name, type_id)
        
class AddNewCovariateForm(QDialog, ui_new_covariate.Ui_new_covariate_dialog):
    
    def __init__(self, parent=None):
        super(AddNewCovariateForm, self).__init__(parent)
        self.setupUi(self)
        self._populate_combo_box()

        
    def _populate_combo_box(self):
        for name, type_id in zip([QString(s) for s in ["Continuous", "Factor"]],
                                     [QVariant(i) for i in range(2)]):
            self.datatype_cbo_box.addItem(name, type_id)