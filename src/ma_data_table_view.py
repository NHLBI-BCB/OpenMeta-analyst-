#############################################################
#  Byron C. Wallace                                         #
#  George Dietz                                             #
#  CEBM @ Brown                                             #
#  OpenMeta(analyst)                                        #
#                                                           #
#                                                           #
# Custom QTableView, implements copy/paste and undo/redo.   #
#############################################################

print("In ma_data_table_view: Importing pyqt4 stuff")
from PyQt4 import QtCore, QtGui
from PyQt4.Qt import *

print("In ma_data_table_view: importing forms")
import binary_data_form
import continuous_data_form
import diagnostic_data_form

# it's a questionable practice to import the
# underlying model into the view, but sometimes
# it's easiest to manipulate the model directly
# on interaction rather than that table_model
# intermediary 
import ma_dataset
from ma_dataset import *
from meta_globals import *

# for issue #169 -- normalizing new lines, e.g., for pasting
# use QRegExp to manipulate QStrings (rather than re)
_newlines_re  = QRegExp('(\r\n|\r|\r)')


def DebugHelper(function):
    def _DebugHelper(*args, **kw):
        print("Entered %s" % function.func_name)
        res = function(*args, **kw)
        print("Left %s" % function.func_name)
        return res
    return _DebugHelper

class MADataTable(QtGui.QTableView):

    def __init__(self, parent=None):
        QWidget.__init__(self, parent)
        
        # the main gui is assumed to be the form
        # that owns this table view, i.e., the 'main'
        # user interface/form. it is assumed that this
        # is set elsewhere.
        self.main_gui = None
        
        # None maps to the special, no outcome/no follow up
        # undo stack
        self.undo_stack_dict = {None:QUndoStack(self)}
        self.undoStack = QUndoStack(self)

        header = self.horizontalHeader()
        self.connect(header, SIGNAL("sectionClicked(int)"), self.header_clicked)

        self.vert_header = self.verticalHeader()
        
        self.connect(self.vert_header, SIGNAL("sectionClicked(int)"),
                     self.row_header_clicked)
    
        ## TODO need to add covariate indices here, as needed
        self.reverse_column_sorts = {0: False, 1: False}
        self.setAlternatingRowColors(True)

        ### horizontal (row) header
        self.contextMenuEvent = self._make_context_menu()

        ### vertical (column) header
        headers = self.horizontalHeader()
        headers.setContextMenuPolicy(Qt.CustomContextMenu)
        headers.customContextMenuRequested.connect(self.header_context_menu)

    def _make_context_menu(self):
        def _context_menu(event):
            context_menu = QMenu(self)
            study_index = self.rowAt(event.y())

            ### if this is a dummy row, it doesn't make
            # sense to provide a context-menu
            if study_index >= len(self.model().dataset.studies):
                return None

            ### delete study
            study = self.model().dataset.studies[study_index]
            action = QAction("delete study %s" % study.name, self)
            QObject.connect(action, SIGNAL("triggered()"), \
                lambda : self.main_gui.delete_study(study, study_index=study_index))
            context_menu.addAction(action)

            ### copy
            action = QAction("copy", self)
            QObject.connect(action, SIGNAL("triggered()"), self.copy)
            context_menu.addAction(action)

            ### paste
            action = QAction("paste", self)
            QObject.connect(action, SIGNAL("triggered()"), self.paste)
            context_menu.addAction(action)

            pos = event.globalPos()
            context_menu.popup(pos)
            event.accept()

        return _context_menu

    def header_context_menu(self, pos):
        '''
        here is where the context menus for column header
        right-clicks are built.
        '''
        column_clicked = self.columnAt(pos.x())
        covariate_columns = self.get_covariate_columns()
        raw_data_columns = self.model().RAW_DATA
        outcomes_columns = self.model().OUTCOMES

        sort_by_col = self.model().get_current_outcome_type()
        data_type = self.model().get_current_outcome_type()

        print "right click @ column: %s" % column_clicked
        context_menu = QMenu(self)

        # add a covariate anywhere
        if column_clicked == 0:
            # option to (de-)select / include all studies
            # per Ethan (issue #100)
            action = QAction("include all", self)
            QObject.connect(action, SIGNAL("triggered()"), self.include_all_studies)
            if self.model().all_studies_are_included():
                action.setEnabled(False)
            context_menu.addAction(action)

            action = QAction("exclude all", self)
            QObject.connect(action, SIGNAL("triggered()"), self.exclude_all_studies)
            if self.model().all_studies_are_excluded():
                action.setEnabled(False)
            context_menu.addAction(action)

            context_menu.popup(self.mapToGlobal(pos))
        elif column_clicked in (1,2):
            col_name = {1:"study name", 2:"year"}[column_clicked]
            action_sort = QAction("sort studies by %s" % col_name, self)
            
            QObject.connect(action_sort, SIGNAL("triggered()"), lambda: self.sort_by_col(column_clicked))
            context_menu.addAction(action_sort)

        elif column_clicked in raw_data_columns and not data_type == "diagnostic":
            corresponding_tx_group = self.model().current_txs[0]
            if data_type == "binary":
                if column_clicked in raw_data_columns[2:]:
                    corresponding_tx_group = self.model().current_txs[1]
            elif data_type == "continuous":
                if column_clicked in raw_data_columns[3:]:
                    corresponding_tx_group = self.model().current_txs[1]
            
            #renaming
            action_rename = QAction("rename group %s..." % corresponding_tx_group, self)
            QObject.connect(action_rename, SIGNAL("triggered()"),
                        lambda : self.main_gui.edit_group_name(corresponding_tx_group))
            context_menu.addAction(action_rename)
            # sorting
            col_name = self.model().headerData(column_clicked, Qt.Horizontal).toString()
            action_sort = QAction("sort studies by %s" % col_name, self)
            QObject.connect(action_sort, SIGNAL("triggered()"),
                        lambda : self.sort_by_col(column_clicked))
            context_menu.addAction(action_sort)
        elif column_clicked in raw_data_columns and data_type == "diagnostic":
            # sorting
            col_name = self.model().headerData(column_clicked, Qt.Horizontal).toString()
            action_sort = QAction("sort studies by %s" % col_name, self)
            QObject.connect(action_sort, SIGNAL("triggered()"),
                        lambda : self.sort_by_col(column_clicked))
            context_menu.addAction(action_sort)
        elif column_clicked in outcomes_columns:
            # sorting
            col_name = self.model().headerData(column_clicked, Qt.Horizontal).toString()
            action_sort = QAction("sort studies by %s" % col_name, self)
            QObject.connect(action_sort, SIGNAL("triggered()"),
                        lambda : self.sort_by_col(column_clicked))
            context_menu.addAction(action_sort)
        elif column_clicked in covariate_columns:
            cov = self.model().get_cov(column_clicked)

            # and for sorting (issue #142)
            action_sort = QAction("sort studies by %s" % cov.name, self)
            QObject.connect(action_sort, SIGNAL("triggered()"),
                        lambda : self.sort_by_col(column_clicked))
            context_menu.addAction(action_sort)

            action_ren = QAction("rename covariate %s" % cov.name, self)
            QObject.connect(action_ren, SIGNAL("triggered()"),
                        lambda : self.main_gui.rename_covariate(cov))
            context_menu.addAction(action_ren)

            # allow deletion of covariate
            action_del = QAction("delete covariate %s" % cov.name, self)
            QObject.connect(action_del, SIGNAL("triggered()"),
                        lambda : self.main_gui.delete_covariate(cov))
            context_menu.addAction(action_del)

            convert_to_str = "*continuous*"
            if cov.data_type == CONTINUOUS:
                convert_to_str = "*factor*"

            action_change = QAction("create a %s copy of %s" % (convert_to_str, cov.name), self)
            QObject.connect(action_change, SIGNAL("triggered()"),
                        lambda : self.main_gui.change_cov_type(cov))
            context_menu.addAction(action_change)
            

        context_menu.popup(self.mapToGlobal(pos))

    def include_all_studies(self):
        self.model().include_all_studies()
        self.model().reset()

    def exclude_all_studies(self):
        self.model().exclude_all_studies()
        self.model().reset()

    def keyPressEvent(self, event):                                  
        if (event.modifiers() & QtCore.Qt.ControlModifier):
            ## undo/redo

            if event.key() == QtCore.Qt.Key_Z:
                self.undoStack.undo()
            elif event.key() == QtCore.Qt.Key_Y:
                self.undoStack.redo()
            ### copy/paste
            elif event.key() == QtCore.Qt.Key_C:
                # ctrl + c = copy
                self.copy()
            elif event.key() == QtCore.Qt.Key_V:
                # ctrl + v = paste
                self.paste()
            else:
                ###
                # if the command hasn't anything to do with the table view
                # in particular, we pass the event up to the main UI
                self.main_gui.keyPressEvent(event)
        else:
            # fix for issue #180
            #if event.key() == QtCore.Qt.Key_Tab:
                # check to see if the next cell is
                # an outcome cell; if it is, treat
                # this like an enter, instead of a tab.
         


            ### 
            # This is a call to the default keyPressEvent function,
            # which we are here overwriting, thereby eliminating
            # many of the annoying properties (no tab navigation; double
            # click editing only) that have been brought up/reported
            # as bugs. See issues: #21, #19
            # 
            QTableView.keyPressEvent(self, event)

            
                         
    def copy(self):
        # copy/paste: these only happen if at least one cell is selected
        selected_indexes = self.selectionModel().selectedIndexes()
        upper_left_index  = self._upper_left(selected_indexes)
        lower_right_index = self._lower_right(selected_indexes)  
        self.copy_contents_in_range(upper_left_index, lower_right_index,
                                    to_clipboard=True)   
                                                                                    
    def paste(self):
        # copy/paste: these only happen if at least one cell is selected
        selected_indexes = self.selectionModel().selectedIndexes()
        upper_left_index  = self._upper_left(selected_indexes)
        lower_right_index = self._lower_right(selected_indexes)

        self.paste_from_clipboard(upper_left_index)     
        self._enable_analysis_menus_if_appropriate()
                                               
    def row_header_clicked(self, row):
        if row > len(self.model().dataset) - 1:
            return
        
        # fix for issue # 184
        self.vert_header.blockSignals(True)
        
        # dispatch on the data type
        form = None
        study_index = row
        # fix for issue # 183
        ma_unit = copy.deepcopy(self.model().get_current_ma_unit_for_study(study_index))
        old_ma_unit = copy.deepcopy(ma_unit)
        cur_txs = self.model().current_txs
        cur_effect = self.model().current_effect
        cur_group_str = self.model().get_cur_group_str()
        data_type = self.model().get_current_outcome_type()

        ####
        # here we implement undo/redo.
        # in particular, we cache the raw data prior to editing;
        # then undo will simply overwrite the new raw data
        if data_type == "binary":
            ### need to back up
            cur_raw_data_dict = {}
            for group in cur_txs:
                cur_raw_data_dict[group] = list(ma_unit.get_raw_data_for_group(group))
                
            form = binary_data_form.BinaryDataForm2(ma_unit, cur_txs, cur_group_str, cur_effect, conf_level=self.model().get_global_conf_level(), parent=self)
            if form.exec_():
                # push the edit even
                ma_edit = CommandEditMAUnit(self, study_index, ma_unit, old_ma_unit)
                self.undoStack.push(ma_edit)
        elif data_type == "continuous":
            cur_raw_data_dict = {}
            for group_name in cur_txs:
                cur_raw_data_dict[group_name] = list(ma_unit.get_raw_data_for_group(group_name))
                
            #old_raw_data_dict = copy.deepcopy(cur_raw_data_dict)
            form = continuous_data_form.ContinuousDataForm(ma_unit, cur_txs, cur_group_str, cur_effect, conf_level=self.model().get_global_conf_level(), parent=self)
            if form.exec_():
                # update the model; push this event onto the stack
                ma_edit = CommandEditMAUnit(self, study_index, ma_unit, old_ma_unit)
                self.undoStack.push(ma_edit)
        else:
            # then this is diagnostic data
            cur_raw_data_dict = {}
            for group in cur_txs:
                cur_raw_data_dict[group] = list(ma_unit.get_raw_data_for_group(group))

            form = diagnostic_data_form.DiagnosticDataForm(ma_unit, cur_txs, cur_group_str, conf_level=self.model().get_global_conf_level(), parent=self)
            if form.exec_():
                ma_edit = CommandEditMAUnit(self, study_index, ma_unit, old_ma_unit)
                self.undoStack.push(ma_edit)
        self.vert_header.blockSignals(False)

    def rowMoved(self, row, oldIndex, newIndex):
        pass

    def displayed_ma_changed(self):
        cur_outcome = self.model().current_outcome
        cur_follow_up = self.model().current_time_point

    def cell_content_changed(self, index, old_val, new_val, study_added):        
        # Only make a cell edit if the old values and new values are different
        try:
            print("Old val: %s, new val: %s" % (unicode(old_val.toString()), unicode(new_val.toString())))
        except AttributeError:
            print("old val: %s, new val: %s" % (str(old_val), str(new_val)))
            
        if not self._new_eq_old(old_val, new_val):
            cell_edit = CommandCellEdit(self, index, old_val, new_val,
                                        added_study=study_added)
            self.undoStack.push(cell_edit)
        self._enable_analysis_menus_if_appropriate()
            
        # make analysis menus change even when checkbox is (un)checked
        self._enable_analysis_menus_if_appropriate()
            
    def _new_eq_old(self, old, new):
        '''None and "" are the same. Assume old and new are QVariants'''
        
        blank_vals = meta_globals.EMPTY_VALS
        
        # transform into normal string:
        if old is not None:
            #old = str(old.toString())
            old = unicode(old.toString())
        if new is not None:
            #new = str(new.toString())
            new = unicode(new.toString())
        
        if old in blank_vals and new in blank_vals:
            return True
        
        return old==new
        
    
    def change_metric_if_appropriate(self):
        '''
        if: 
            1) there are at least 2 studies, and 
            2) none of them have data for two-arms, and,
            3) the current metric is a two-arm metric
        then:
            we automatically change the metric to single-arm

        returns a tuple, wherein the first element is a boolean
        indicating whether or not the metric was indeed changed,
        and the second is the original metric
        '''
        original_metric = self.model().current_effect
    
        if len(self.model().dataset) > 2:
            data_type = self.model().get_current_outcome_type()
            if data_type == "binary" or data_type == "continuous":
                default_metric = {"binary":BINARY_ONE_ARM_METRICS[0], 
                                  "continuous":CONTINUOUS_ONE_ARM_METRICS[0]}[data_type]
                
                if default_metric != original_metric and self.model().data_for_only_one_arm():
                    self.set_metric_in_ui(default_metric)
                    return (True, original_metric)
        return (False,  original_metric)


    def get_covariate_columns(self):
        return range(self.model().OUTCOMES[-1]+1, self.model().columnCount())

    def header_clicked(self, column):
        can_sort_by = [self.model().NAME, self.model().YEAR]
        ## plus we can sort by any covariates, which correspond to those columns that are
        # beyond the last outcome
        covariate_columns = self.get_covariate_columns()
        can_sort_by.extend(covariate_columns)

    def sort_by_col(self, column):
        # if a covariate column was clicked, it may not yet have an entry in the
        # reverse_column_sorts dictionary; thus we insert one here
        #
        # @TODO this should *not* use the column number as the key!
        # rather, it should use the name -- the column number of a given
        # covariate might change (e.g., if another covariate is deleted)
        if not self.reverse_column_sorts.has_key(column):
            self.reverse_column_sorts[column] = False
        sort_command = CommandSort(self.model(), column, self.reverse_column_sorts[column])
        self.undoStack.push(sort_command)
        self.reverse_column_sorts[column] = not self.reverse_column_sorts[column]

    def _normalize_newlines(self, qstr_text):
        return qstr_text.replace(_newlines_re, "\n")

    def paste_from_clipboard(self, upper_left_index):
        ''' pastes the data in the clipboard starting at the currently selected cell.'''

        clipboard = QApplication.clipboard()
        clipboard_text = clipboard.text()

        # fix for issue #169.
        # excel for mac, insanely, appends \r instead of
        # \n for new lines (rows).
        clipboard_text = self._normalize_newlines(clipboard_text)

        new_content = self._str_to_matrix(clipboard_text)

        # fix for issue #64. excel likes to append a blank row
        # to copied data -- we drop that here
        if self._is_blank_row(new_content[-1]):
            new_content = new_content[:-1]

        lower_row = upper_left_index.row() + len(new_content)
        lower_col = upper_left_index.column() + len(new_content[0])
        print "lower row: %s, lower col: %s" % (lower_row, lower_col)
        num_studies_pre_paste = len(self.model().dataset)
        studies_pre_paste = list(self.model().dataset.studies)
        lower_right_index = self.model().createIndex(lower_row-1, lower_col-1)
        old_content = self._str_to_matrix(self.copy_contents_in_range(upper_left_index, lower_right_index, to_clipboard=False))
        
        print "old content: %s" % old_content
        print "new content: %s" % new_content
        print "upper left index:"
        print self._print_index(upper_left_index)

        paste_command =  CommandPaste(self, new_content, old_content,
                                        upper_left_index, studies_pre_paste,
                                        self.column_widths(), "paste %s" % new_content)
        self.undoStack.push(paste_command)

    def copy_contents_in_range(self, upper_left_index, lower_right_index, to_clipboard):
        '''
        copy the (textual) content of the cells in provided cell_range -- the copied contents will be
        cast to python Unicode strings and returned. If the to_clipboard flag is true, the contents will
        also be copied to the system clipboard
        '''
        print "upper left index: %s, upper right index: %s" % \
                (self._print_index(upper_left_index), self._print_index(lower_right_index))
        text_matrix = []

        # +1s are because range() is right interval exclusive
        for row in range(upper_left_index.row(), lower_right_index.row()+1):
            current_row = []
            for col in range(upper_left_index.column(), lower_right_index.column()+1):
                cur_index = self.model().createIndex(row, col)
                cur_data = self.model().data(cur_index)
                if cur_data is not None:
                    # this looks redundant, but in fact the toString method
                    # converts the string into a QString
                    cur_str = str(cur_data.toString())
                    current_row.append(cur_str)
                else:
                    current_row.append("")
            text_matrix.append(current_row)

        copied_str = self._matrix_to_str(text_matrix)

        if to_clipboard:
            clipboard = QApplication.clipboard()
            clipboard.setText(copied_str)
        print "copied str: %s" % copied_str
        return copied_str

    def paste_contents(self, upper_left_index, source_content):
        '''
        paste the content in source_content into the matrix starting at the upper_left_coord
        cell. new rows will be added as needed; existing data will be overwritten
        '''
        origin_row, origin_col = upper_left_index.row(), upper_left_index.column()

        if isinstance(source_content[-1], QtCore.QStringList) and \
                             len(str(source_content[-1].join(" ")))==0:
            # then there's a blank line; Excel has a habit
            # of appending blank lines (\ns) to copied
            # text -- we get rid of it here
            source_content = source_content[:-1]

        # temporarily disable sorting to prevent automatic sorting of pasted data.
        # (note: this is consistent with Excel's approach.)
        self.model().blockSignals(True)

        for src_row in range(len(source_content)):
            # do we need to append a row?
            cur_row_count = self.model().rowCount()
            if  cur_row_count <= origin_row + src_row:
                self._add_new_row()
             
            for src_col in range(len(source_content[0])):
                try:
                    # note that we treat all of the data pasted as
                    # one event; i.e., when undo is called, it undos the
                    # whole paste
                    index = self.model().createIndex(origin_row+src_row, origin_col+src_col)
                    self.model().setData(index, QVariant(source_content[src_row][src_col]))
                except Exception, e:
                    print "whoops, exception while pasting: %s" % e

        self.model().blockSignals(False)
        self.model().reset()

    def set_data_in_model(self, index, val):
        self.model().setData(index, val)
        self.model().reset()

    def column_widths(self):
        ''' returns the current column widths '''
        return [self.columnWidth(col_index) for col_index in range(self.model().columnCount())]

    def set_column_widths(self, widths):
        for col_index, width in enumerate(widths):
            self.setColumnWidth(col_index, width)


    def set_metric_in_ui(self, metric):
        '''
        calls the method on the UI to change
        the current metric -- this is the same
        method binded to the menu items, so call
        this to programmatically change the metric.
        '''
        menu = self.main_gui.oneArmMetricMenu
        if metric in TWO_ARM_METRICS:
            menu = self.main_gui.twoArmMetricMenu
        self.main_gui.metric_selected(metric, menu)

    def _enable_analysis_menus_if_appropriate(self):
        
        if len(self.model().dataset) >= 2 and self._get_number_of_included_studies() >= 2: #TODO add condition that there are at least two studies included
            self.main_gui.enable_menu_options_that_require_dataset()
        else:
            self.main_gui.disable_menu_options_that_require_dataset()
    
    def _get_number_of_included_studies(self):
        studies = self.model().dataset.studies
        num_included = 0
        for study in studies:
            if study.include and (not study.manually_excluded):
                num_included += 1
            print("included: %s, manually excluded: %s" % (str(study.include), str(study.manually_excluded)))
        print("num included: %d" % num_included)
        return num_included

    def _print_index(self, index):
        print "(%s, %s)" % (index.row(), index.column())

    def _add_new_row(self):
        '''
        add a new row to the dataTable; note that we briefly toggle sorting off so the row
        is beneath the existing rows.
        '''
        model = self.model()
        cur_row_count = model.rowCount()
        model.insertRow(cur_row_count)

    def _str_to_matrix(self, text, col_delimiter="\t", row_delimiter="\n"):
        ''' transforms raw text (e.g., from the clipboard) to a structured matrix '''
        m = []
        rows  = text.split(row_delimiter)
        for row in rows:
            cur_row = row.split(col_delimiter)
            m.append(cur_row)
        return m

    def _print_row(self, r):
        print "length of row: %s" % len(r)
        for x in r:
            print x == ""
            print "%s," % x
        print "\n"

    def _is_blank_row(self, r):
        return len(r) == 1 and r[0] == ""

    def _matrix_to_str(self, m, col_delimiter="\t", row_delimiter="\n", append_new_line =False):
        ''' takes a matrix of data (i.e., a nested list) and converts to a string representation '''
        m_str = []
        for row in m:
            m_str.append(col_delimiter.join(row))
        return_str = row_delimiter.join(m_str)
        if append_new_line:
            return_str += row_delimiter
        return return_str

    def _upper_left(self, indexes):
        ''' returns the upper most index object in the indexes list.'''
        if len(indexes) > 0:
            upper_left = indexes[0]
            for index in indexes[1:]:
                if index.row() < upper_left.row() or index.column() < upper_left.column():
                    upper_left = index
            return upper_left
        return None

    def _lower_right(self, indexes):
        if len(indexes) > 0:
            lower_right = indexes[0]
            for index in indexes[1:]:
                if index.row() > lower_right.row() or index.column() > lower_right.column():
                    lower_right = index
            return lower_right
        return None

    def _add_studies_if_necessary(self, upper_left_index, content):
        '''
        if there are not enough studies to contain the content, this will 
        add them.
        '''
        origin_row, origin_col = upper_left_index.row(), upper_left_index.column()
        num_existing_studies = len(self.model().dataset)

        num_to_add = len(content) - num_existing_studies - origin_row

        last_id = -1
        for i in range(num_to_add):
            # first let's give this a default study name, in case
            # none has been provided
            tmp_study_name = "study %s" % (num_existing_studies + i)
            study_index = self.model().createIndex(num_existing_studies + i, self.model().NAME)
            study_id = self.model().dataset.max_study_id()+1
            new_study = Study(study_id)
            self.model().dataset.add_study(new_study)

        # now append a blank study if studies were added.
        if num_to_add > 0:
            new_study = Study(self.model().dataset.max_study_id()+1)
            # ah! fix for issue #171. stupidly, I was not previously
            # excluding 'blank' studies appended here..
            new_study.include = False
            self.model().dataset.add_study(new_study)
            self.model().dataset.study_auto_added = int(new_study.id)

        self.model().reset()

class CommandCellEdit(QUndoCommand):
    '''
    Here we make use of QT's undo/redo framework. This is an UndoCommand for individual
    cell edits (as opposed to paste actions, which are represented by CommandPaste objects,
    defined below).
    '''
    def __init__(self, ma_data_table_view, index, original_content, new_content, 
                 ####metric_changed=False, old_metric=None, new_metric=None, # DELETE IF ALL IS WELL
                 added_study=None,
                 description=""):
        super(CommandCellEdit, self).__init__(description)
        self.first_call = True
        if original_content == None:
            self.original_content = QVariant(QString(""))
        else:
            self.original_content = original_content
        self.new_content = new_content
        self.row, self.col = index.row(), index.column()
        self.ma_data_table_view = ma_data_table_view
        self.added_study = added_study
        self.something_else = added_study
        
        #### output for debugging
        debug_params = dict(first_call = True,
            original_content = original_content,
            new_content = new_content,
            row = index.row(),
            col = index.column(),
            ma_data_table_view = ma_data_table_view,
            added_study = added_study,
            something_else = added_study,
            )

        print("CommandCellEdit created with parameters: %s" % str(debug_params))
        #### end debugging output

    @DebugHelper
    def redo(self):
        index = self._get_index()
     
        if self.first_call:
            self.first_call = False
            ###
            # the self.added_study should be true if and only if
            # the event being done *caused* a study to be added.
            # in this case, we'll need to remove the added study
            # on the undo() call
            

            #self.added_study = self.ma_data_table_view.model().study_auto_added
            # note: previously (10/14/11) there was a call here to set the
            # model's study_auto_added field to None. I don't know why it was
            # here, and removed it.  
            #     > self.ma_data_table_view.model().study_auto_added = None
        else:
            model = self.ma_data_table_view.model()
            # here we block signals from the model. this is
            # to prevent memory access problems on the c
            # side of things, when the model emits
            # the data edited signal.
            model.blockSignals(True)
            model.setData(index, self.new_content)
            self.added_study = self.ma_data_table_view.model().study_auto_added
            self.ma_data_table_view.model().study_auto_added = None

            model.blockSignals(False)
            # make the view reflect the update
            self.ma_data_table_view.model().reset()
        
        self.ma_data_table_view._enable_analysis_menus_if_appropriate()
        self.ma_data_table_view.resizeColumnsToContents()

        # let everyone know that the data is dirty
        self.ma_data_table_view.emit(SIGNAL("dataDirtied()"))

    @DebugHelper
    def undo(self):
        # in this case, the original editing action
        # had the effect of appending a row to the spreadsheet.
        # here we remove it.
        if self.added_study is not None:
            self.ma_data_table_view.model().remove_study(self.added_study)

        index = self._get_index()
        model = self.ma_data_table_view.model()

        # as in the redo method, we block signals before
        # editing the model data
        model.blockSignals(True)
        model.setData(index, self.original_content, allow_empty_names=True)

        model.blockSignals(False)
        self.ma_data_table_view.model().reset()

            
        # here is where we check if there are enough studies to actually
        # perform an analysis.
        self.ma_data_table_view._enable_analysis_menus_if_appropriate()
        self.ma_data_table_view.resizeColumnsToContents()
        self.ma_data_table_view.emit(SIGNAL("dataDirtied()"))
        
    def _get_index(self):
        return self.ma_data_table_view.model().createIndex(self.row, self.col)

    
class CommandPaste(QUndoCommand):
    '''
    We again make use of QT's undo/redo framework. this implementation handles the paste action;
    the redo is just repasting the former contents into the same cells.
    '''
    def __init__(self, ma_data_table_view, new_content, old_content,\
                    upper_left_coord, old_studies, old_col_widths, description):
        super(CommandPaste, self).__init__(description)
        self.new_content, self.old_content = new_content, old_content
        self.upper_left_coord = upper_left_coord
        self.old_column_widths = old_col_widths
        self.ma_data_table_view = ma_data_table_view
        self.added_study = None
        self.metric_changed = None
        self.old_metric = None
        self.new_metric = None
        # is this the first time? 
        self.first_call = True

        print("CommandPaste created")
    
    @DebugHelper
    def redo(self):
        # cache the original dataset
        self.original_dataset = copy.deepcopy(self.ma_data_table_view.model().dataset)
        self.original_state_dict = copy.copy(self.ma_data_table_view.model().get_stateful_dict())

        # paste the data
        self.ma_data_table_view._add_studies_if_necessary(self.upper_left_coord, self.new_content)
        self.ma_data_table_view.paste_contents(self.upper_left_coord, self.new_content)

        if self.first_call:
            # on the first application of the paste, we need to ascertain
            # whether the metric changed automatically (e.g., because it
            # looks like tpasted data is single-arm)
            self.metric_changed, self.old_metric = \
                self.ma_data_table_view.change_metric_if_appropriate()

            if self.metric_changed:
                self.new_metric = self.ma_data_table_view.model().current_effect
                #self.ma_data_table_view.set_metric_in_ui(self.new_metric)
            self.first_call = False
        else:
            # did the metric change on the original paste? 
            # if so re-change it here
            if self.metric_changed is not None:
                self.ma_data_table_view.set_metric_in_ui(self.new_metric)

        self.ma_data_table_view.model().reset()
        self.ma_data_table_view._enable_analysis_menus_if_appropriate()
        self.ma_data_table_view.emit(SIGNAL("dataDirtied()"))
        self.ma_data_table_view.resizeColumnsToContents()

    @DebugHelper
    def undo(self):
        if self.added_study is not None:
            self.ma_data_table_view.model().remove_study(self.added_study)
        self.ma_data_table_view.main_gui.set_model(self.original_dataset,
                                 state_dict=self.original_state_dict)


        # did we change the metric automatically (e.g., because it
        # looked like the user was exploring single-arm data?) if
        # so, change it back
        if self.metric_changed:
            self.ma_data_table_view.set_metric_in_ui(self.old_metric)

        self.ma_data_table_view.model().reset()
        self.ma_data_table_view._enable_analysis_menus_if_appropriate()
        self.ma_data_table_view.emit(SIGNAL("dataDirtied()"))

class CommandEditMAUnit(QUndoCommand):
    def __init__(self, table_view, study_index, new_ma_unit, old_ma_unit, description="MA unit edit"):
        super(CommandEditMAUnit, self).__init__(description)
        self.model = table_view.model()
        self.old_ma_unit = old_ma_unit
        self.new_ma_unit = new_ma_unit
        self.table_view = table_view
        self.study_index = study_index
        self.ma_data_table_view = table_view
        
        # for debugging
        print("CommandEditMAunit created")
    
    @DebugHelper
    def undo(self):
        self.model.set_current_ma_unit_for_study(self.study_index, self.old_ma_unit)
        self.model.reset()
        self.table_view.resizeColumnsToContents()
        self.ma_data_table_view.emit(SIGNAL("dataDirtied()"))

    @DebugHelper
    def redo(self):
        self.model.set_current_ma_unit_for_study(self.study_index, self.new_ma_unit)
        self.model.reset()
        self.model.try_to_update_outcomes()
        
        #self.table_view.model().reset()
        self.table_view.resizeColumnsToContents()
        self.ma_data_table_view.emit(SIGNAL("dataDirtied()"))

# IS THIS CLASS USED ANYWHERE?
class CommandEditRawData(QUndoCommand):
    def __init__(self, ma_unit, model, old_raw_data_dict, new_raw_data_dict, description="Raw data edit"):
        super(CommandEditRawData, self).__init__(description)
        self.ma_unit = ma_unit
        # we take the model in as a parameter so we can call reset(), in turn
        # notifying the view to refresh. otherwise, the old data is displayed
        # until the user interacts with it in some way
        self.model = model 
        self.old_raw_data_dict = old_raw_data_dict
        self.new_raw_data_dict = new_raw_data_dict
        self.group_names = self.old_raw_data_dict.keys()
        
        print("Command Edit RawData created")
    
    @DebugHelper
    def undo(self):
        for group_name in self.group_names:
            raw_data = self.old_raw_data_dict[group_name]
            self.ma_unit.set_raw_data_for_group(group_name, raw_data)
        self.model.reset()
        self.ma_data_table_view.emit(SIGNAL("dataDirtied()"))

    @DebugHelper
    def redo(self):
        for group_name in self.group_names:
            raw_data = self.new_raw_data_dict[group_name]
            self.ma_unit.set_raw_data_for_group(group_name, raw_data)
        self.model.reset()
        self.ma_data_table_view.emit(SIGNAL("dataDirtied()"))

class CommandSort(QUndoCommand):
    def __init__(self, ma_data_table_model, col, reverse_order, description="Sort"):
        super(CommandSort, self).__init__(description)
        self.model = ma_data_table_model
        self.col = col
        self.reverse = reverse_order
        self.previous_order = None
        
        print("CommandSort created")

    def redo(self):
        self.previous_order = self.model.get_ordered_study_ids()
        self.model.sort_studies(self.col, self.reverse)
        self.model.reset()

    def undo(self):
        self.model.order_studies(self.previous_order)
        self.model.reset()
        
class StudyDelegate(QItemDelegate):

    def __init__(self, parent=None):
        super(StudyDelegate, self).__init__(parent)

    def createEditor(self, parent, *args):
        le = QLineEdit(parent)
        return le

    def setEditorData(self, editor, index):
        # used to be Qt.DisplayRole
        text = index.model().data(index, Qt.EditRole)
        editor.setText(text.toString())

