# -*- coding: utf-8 -*-

# Form implementation generated from reading ui file 'binary_data_form2.ui'
#
# Created: Wed Oct 27 13:43:26 2010
#      by: PyQt4 UI code generator 4.7.3
#
# WARNING! All changes made in this file will be lost!

from PyQt4 import QtCore, QtGui

class Ui_BinaryDataForm(object):
    def setupUi(self, BinaryDataForm):
        BinaryDataForm.setObjectName("BinaryDataForm")
        BinaryDataForm.resize(386, 300)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        BinaryDataForm.setFont(font)
        self.layoutWidget_5 = QtGui.QWidget(BinaryDataForm)
        self.layoutWidget_5.setGeometry(QtCore.QRect(10, 250, 359, 41))
        self.layoutWidget_5.setObjectName("layoutWidget_5")
        self.horizontalLayout = QtGui.QHBoxLayout(self.layoutWidget_5)
        self.horizontalLayout.setSpacing(6)
        self.horizontalLayout.setContentsMargins(36, 3, -1, -1)
        self.horizontalLayout.setObjectName("horizontalLayout")
        spacerItem = QtGui.QSpacerItem(160, 20, QtGui.QSizePolicy.Fixed, QtGui.QSizePolicy.Minimum)
        self.horizontalLayout.addItem(spacerItem)
        self.buttonBox = QtGui.QDialogButtonBox(self.layoutWidget_5)
        self.buttonBox.setOrientation(QtCore.Qt.Horizontal)
        self.buttonBox.setStandardButtons(QtGui.QDialogButtonBox.Cancel|QtGui.QDialogButtonBox.Ok)
        self.buttonBox.setObjectName("buttonBox")
        self.horizontalLayout.addWidget(self.buttonBox)
        self.widget = QtGui.QWidget(BinaryDataForm)
        self.widget.setGeometry(QtCore.QRect(10, 10, 363, 238))
        self.widget.setObjectName("widget")
        self.verticalLayout_3 = QtGui.QVBoxLayout(self.widget)
        self.verticalLayout_3.setObjectName("verticalLayout_3")
        self.verticalLayout_2 = QtGui.QVBoxLayout()
        self.verticalLayout_2.setObjectName("verticalLayout_2")
        self.verticalLayout = QtGui.QVBoxLayout()
        self.verticalLayout.setObjectName("verticalLayout")
        self.gridLayout = QtGui.QGridLayout()
        self.gridLayout.setContentsMargins(-1, -1, -1, 9)
        self.gridLayout.setVerticalSpacing(4)
        self.gridLayout.setObjectName("gridLayout")
        self.label_5 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_5.setFont(font)
        self.label_5.setAlignment(QtCore.Qt.AlignCenter)
        self.label_5.setObjectName("label_5")
        self.gridLayout.addWidget(self.label_5, 0, 1, 1, 1)
        self.label_6 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_6.setFont(font)
        self.label_6.setAlignment(QtCore.Qt.AlignCenter)
        self.label_6.setObjectName("label_6")
        self.gridLayout.addWidget(self.label_6, 0, 2, 1, 1)
        self.label_10 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        font.setWeight(75)
        font.setBold(True)
        self.label_10.setFont(font)
        self.label_10.setAlignment(QtCore.Qt.AlignCenter)
        self.label_10.setObjectName("label_10")
        self.gridLayout.addWidget(self.label_10, 0, 3, 1, 1)
        self.label_3 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_3.setFont(font)
        self.label_3.setAlignment(QtCore.Qt.AlignBottom|QtCore.Qt.AlignRight|QtCore.Qt.AlignTrailing)
        self.label_3.setObjectName("label_3")
        self.gridLayout.addWidget(self.label_3, 1, 0, 1, 1)
        self.raw_data_table = QtGui.QTableWidget(self.widget)
        sizePolicy = QtGui.QSizePolicy(QtGui.QSizePolicy.Expanding, QtGui.QSizePolicy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.raw_data_table.sizePolicy().hasHeightForWidth())
        self.raw_data_table.setSizePolicy(sizePolicy)
        self.raw_data_table.setMinimumSize(QtCore.QSize(305, 93))
        self.raw_data_table.setMaximumSize(QtCore.QSize(305, 84))
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.raw_data_table.setFont(font)
        self.raw_data_table.setFrameShadow(QtGui.QFrame.Plain)
        self.raw_data_table.setLineWidth(1)
        self.raw_data_table.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.raw_data_table.setHorizontalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.raw_data_table.setProperty("showDropIndicator", True)
        self.raw_data_table.setAlternatingRowColors(True)
        self.raw_data_table.setShowGrid(True)
        self.raw_data_table.setGridStyle(QtCore.Qt.DashDotLine)
        self.raw_data_table.setRowCount(3)
        self.raw_data_table.setColumnCount(3)
        self.raw_data_table.setObjectName("raw_data_table")
        self.raw_data_table.setColumnCount(3)
        self.raw_data_table.setRowCount(3)
        self.raw_data_table.horizontalHeader().setVisible(False)
        self.raw_data_table.horizontalHeader().setHighlightSections(False)
        self.raw_data_table.verticalHeader().setVisible(False)
        self.gridLayout.addWidget(self.raw_data_table, 1, 1, 3, 3)
        self.label_4 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_4.setFont(font)
        self.label_4.setAlignment(QtCore.Qt.AlignRight|QtCore.Qt.AlignTrailing|QtCore.Qt.AlignVCenter)
        self.label_4.setObjectName("label_4")
        self.gridLayout.addWidget(self.label_4, 2, 0, 1, 1)
        self.label_9 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        font.setWeight(75)
        font.setBold(True)
        self.label_9.setFont(font)
        self.label_9.setAlignment(QtCore.Qt.AlignRight|QtCore.Qt.AlignTrailing|QtCore.Qt.AlignVCenter)
        self.label_9.setObjectName("label_9")
        self.gridLayout.addWidget(self.label_9, 3, 0, 1, 1)
        self.verticalLayout.addLayout(self.gridLayout)
        self.horizontalLayout_3 = QtGui.QHBoxLayout()
        self.horizontalLayout_3.setObjectName("horizontalLayout_3")
        spacerItem1 = QtGui.QSpacerItem(188, 20, QtGui.QSizePolicy.Expanding, QtGui.QSizePolicy.Minimum)
        self.horizontalLayout_3.addItem(spacerItem1)
        self.label_11 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_11.setFont(font)
        self.label_11.setObjectName("label_11")
        self.horizontalLayout_3.addWidget(self.label_11)
        self.chi_txt_box_2 = QtGui.QTextEdit(self.widget)
        self.chi_txt_box_2.setMinimumSize(QtCore.QSize(40, 19))
        self.chi_txt_box_2.setMaximumSize(QtCore.QSize(40, 19))
        font = QtGui.QFont()
        font.setFamily("Verdana")
        font.setPointSize(8)
        self.chi_txt_box_2.setFont(font)
        self.chi_txt_box_2.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.chi_txt_box_2.setObjectName("chi_txt_box_2")
        self.horizontalLayout_3.addWidget(self.chi_txt_box_2)
        self.label_12 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_12.setFont(font)
        self.label_12.setObjectName("label_12")
        self.horizontalLayout_3.addWidget(self.label_12)
        self.chi_p_txt_box_2 = QtGui.QTextEdit(self.widget)
        self.chi_p_txt_box_2.setMinimumSize(QtCore.QSize(40, 19))
        self.chi_p_txt_box_2.setMaximumSize(QtCore.QSize(40, 19))
        font = QtGui.QFont()
        font.setFamily("Verdana")
        font.setPointSize(8)
        self.chi_p_txt_box_2.setFont(font)
        self.chi_p_txt_box_2.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAlwaysOff)
        self.chi_p_txt_box_2.setObjectName("chi_p_txt_box_2")
        self.horizontalLayout_3.addWidget(self.chi_p_txt_box_2)
        self.verticalLayout.addLayout(self.horizontalLayout_3)
        self.verticalLayout_2.addLayout(self.verticalLayout)
        self.horizontalLayout_4 = QtGui.QHBoxLayout()
        self.horizontalLayout_4.setObjectName("horizontalLayout_4")
        self.label_13 = QtGui.QLabel(self.widget)
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_13.setFont(font)
        self.label_13.setAlignment(QtCore.Qt.AlignBottom|QtCore.Qt.AlignLeading|QtCore.Qt.AlignLeft)
        self.label_13.setObjectName("label_13")
        self.horizontalLayout_4.addWidget(self.label_13)
        self.effect_cbo_box = QtGui.QComboBox(self.widget)
        self.effect_cbo_box.setMinimumSize(QtCore.QSize(76, 20))
        self.effect_cbo_box.setMaximumSize(QtCore.QSize(76, 20))
        self.effect_cbo_box.setObjectName("effect_cbo_box")
        self.horizontalLayout_4.addWidget(self.effect_cbo_box)
        self.verticalLayout_2.addLayout(self.horizontalLayout_4)
        self.verticalLayout_3.addLayout(self.verticalLayout_2)
        self.effect_grp_box = QtGui.QGroupBox(self.widget)
        self.effect_grp_box.setMinimumSize(QtCore.QSize(360, 50))
        self.effect_grp_box.setMaximumSize(QtCore.QSize(360, 50))
        self.effect_grp_box.setTitle("")
        self.effect_grp_box.setObjectName("effect_grp_box")
        self.layoutWidget_4 = QtGui.QWidget(self.effect_grp_box)
        self.layoutWidget_4.setGeometry(QtCore.QRect(0, 0, 351, 41))
        self.layoutWidget_4.setObjectName("layoutWidget_4")
        self.gridLayout_3 = QtGui.QGridLayout(self.layoutWidget_4)
        self.gridLayout_3.setObjectName("gridLayout_3")
        self.label_14 = QtGui.QLabel(self.layoutWidget_4)
        self.label_14.setMinimumSize(QtCore.QSize(0, 20))
        self.label_14.setMaximumSize(QtCore.QSize(16777215, 20))
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_14.setFont(font)
        self.label_14.setAlignment(QtCore.Qt.AlignBottom|QtCore.Qt.AlignLeading|QtCore.Qt.AlignLeft)
        self.label_14.setObjectName("label_14")
        self.gridLayout_3.addWidget(self.label_14, 0, 0, 1, 1)
        self.label_15 = QtGui.QLabel(self.layoutWidget_4)
        self.label_15.setMaximumSize(QtCore.QSize(16777215, 20))
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_15.setFont(font)
        self.label_15.setAlignment(QtCore.Qt.AlignBottom|QtCore.Qt.AlignLeading|QtCore.Qt.AlignLeft)
        self.label_15.setObjectName("label_15")
        self.gridLayout_3.addWidget(self.label_15, 0, 2, 1, 1)
        self.label_16 = QtGui.QLabel(self.layoutWidget_4)
        self.label_16.setMaximumSize(QtCore.QSize(16777215, 20))
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_16.setFont(font)
        self.label_16.setAlignment(QtCore.Qt.AlignBottom|QtCore.Qt.AlignLeading|QtCore.Qt.AlignLeft)
        self.label_16.setObjectName("label_16")
        self.gridLayout_3.addWidget(self.label_16, 0, 4, 1, 1)
        self.label_17 = QtGui.QLabel(self.layoutWidget_4)
        self.label_17.setMaximumSize(QtCore.QSize(16777215, 20))
        font = QtGui.QFont()
        font.setFamily("Verdana")
        self.label_17.setFont(font)
        self.label_17.setAlignment(QtCore.Qt.AlignBottom|QtCore.Qt.AlignLeading|QtCore.Qt.AlignLeft)
        self.label_17.setObjectName("label_17")
        self.gridLayout_3.addWidget(self.label_17, 0, 6, 1, 1)
        self.effect_txt_box = QtGui.QLineEdit(self.layoutWidget_4)
        self.effect_txt_box.setMinimumSize(QtCore.QSize(50, 22))
        self.effect_txt_box.setMaximumSize(QtCore.QSize(50, 22))
        self.effect_txt_box.setObjectName("effect_txt_box")
        self.gridLayout_3.addWidget(self.effect_txt_box, 0, 1, 1, 1)
        self.low_txt_box = QtGui.QLineEdit(self.layoutWidget_4)
        self.low_txt_box.setMinimumSize(QtCore.QSize(50, 22))
        self.low_txt_box.setMaximumSize(QtCore.QSize(50, 22))
        self.low_txt_box.setObjectName("low_txt_box")
        self.gridLayout_3.addWidget(self.low_txt_box, 0, 3, 1, 1)
        self.high_txt_box = QtGui.QLineEdit(self.layoutWidget_4)
        self.high_txt_box.setMinimumSize(QtCore.QSize(50, 22))
        self.high_txt_box.setMaximumSize(QtCore.QSize(50, 22))
        self.high_txt_box.setObjectName("high_txt_box")
        self.gridLayout_3.addWidget(self.high_txt_box, 0, 5, 1, 1)
        self.effect_p_txt_box = QtGui.QLineEdit(self.layoutWidget_4)
        self.effect_p_txt_box.setMinimumSize(QtCore.QSize(50, 22))
        self.effect_p_txt_box.setMaximumSize(QtCore.QSize(50, 22))
        self.effect_p_txt_box.setObjectName("effect_p_txt_box")
        self.gridLayout_3.addWidget(self.effect_p_txt_box, 0, 7, 1, 1)
        self.verticalLayout_3.addWidget(self.effect_grp_box)
        self.widget1 = QtGui.QWidget(BinaryDataForm)
        self.widget1.setGeometry(QtCore.QRect(0, 0, 2, 2))
        self.widget1.setObjectName("widget1")
        self.verticalLayout_4 = QtGui.QVBoxLayout(self.widget1)
        self.verticalLayout_4.setObjectName("verticalLayout_4")

        self.retranslateUi(BinaryDataForm)
        QtCore.QObject.connect(self.buttonBox, QtCore.SIGNAL("accepted()"), BinaryDataForm.accept)
        QtCore.QObject.connect(self.buttonBox, QtCore.SIGNAL("rejected()"), BinaryDataForm.reject)
        QtCore.QMetaObject.connectSlotsByName(BinaryDataForm)

    def retranslateUi(self, BinaryDataForm):
        BinaryDataForm.setWindowTitle(QtGui.QApplication.translate("BinaryDataForm", "Dialog", None, QtGui.QApplication.UnicodeUTF8))
        self.label_5.setText(QtGui.QApplication.translate("BinaryDataForm", "event", None, QtGui.QApplication.UnicodeUTF8))
        self.label_6.setText(QtGui.QApplication.translate("BinaryDataForm", "no event", None, QtGui.QApplication.UnicodeUTF8))
        self.label_10.setText(QtGui.QApplication.translate("BinaryDataForm", "total", None, QtGui.QApplication.UnicodeUTF8))
        self.label_3.setText(QtGui.QApplication.translate("BinaryDataForm", "group 1", None, QtGui.QApplication.UnicodeUTF8))
        self.label_4.setText(QtGui.QApplication.translate("BinaryDataForm", "group 2", None, QtGui.QApplication.UnicodeUTF8))
        self.label_9.setText(QtGui.QApplication.translate("BinaryDataForm", "total", None, QtGui.QApplication.UnicodeUTF8))
        self.label_11.setText(QtGui.QApplication.translate("BinaryDataForm", "χ²", None, QtGui.QApplication.UnicodeUTF8))
        self.label_12.setText(QtGui.QApplication.translate("BinaryDataForm", " χ² p-val", None, QtGui.QApplication.UnicodeUTF8))
        self.label_13.setText(QtGui.QApplication.translate("BinaryDataForm", "effect", None, QtGui.QApplication.UnicodeUTF8))
        self.label_14.setText(QtGui.QApplication.translate("BinaryDataForm", "est.", None, QtGui.QApplication.UnicodeUTF8))
        self.label_15.setText(QtGui.QApplication.translate("BinaryDataForm", "low", None, QtGui.QApplication.UnicodeUTF8))
        self.label_16.setText(QtGui.QApplication.translate("BinaryDataForm", "high", None, QtGui.QApplication.UnicodeUTF8))
        self.label_17.setText(QtGui.QApplication.translate("BinaryDataForm", "p-val", None, QtGui.QApplication.UnicodeUTF8))

