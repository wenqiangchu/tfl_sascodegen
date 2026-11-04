/* External runner binds RESULTS to a case-specific output directory. */
proc sql noprint;
  create table results.table_inventory as
  select memname, nobs, nvar, obslen, filesize from dictionary.tables
  where libname='WORK' and substr(memname,1,5)='_TFL_';
  create table results.column_inventory as
  select memname, name, type, length, varnum, format, informat, label
  from dictionary.columns
  where libname='WORK' and substr(memname,1,5)='_TFL_';
  select memname into :runtime_capture separated by ' '
  from dictionary.tables where libname='WORK' and
    (memname in ('_TFL_ASM_001','_TFL_WIDE_001','_TFL_CELLS_001')
     or substr(memname,1,8)='_TFL_HN_'
     or substr(memname,1,12)='_TFL_HNODES_'
     or index(memname,'_TFL_HFMTRAW_')=1 or index(memname,'_TFL_HFCAT_')=1
     or substr(memname,1,10) in ('_TFL_CRAW_','_TFL_KRAW_','_TFL_STAT_')
     or substr(memname,1,12)='_TFL_KDUNIT_');
quit;
proc datasets library=work nolist;
  copy out=results;
  select &runtime_capture;
quit;
%put NOTE: [RUNTIME] capture complete;
