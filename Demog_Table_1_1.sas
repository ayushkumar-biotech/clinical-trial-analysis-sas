/*==========================================================================
  PROGRAM   : Demog_Table_1_1.sas
  PURPOSE   : Table 1.1 - Demographic and Baseline Characteristics
              by Treatment Group (Randomized Population)
  INPUT     : M4_T1_V2_-_project_-_demog.xlsx  (sheet = demog)
  VARIABLES : STUDY PATNO SITENO SUBJINI DIAGDT DAY MONTH YEAR GENDER RACE TRT
==========================================================================*/


/*-------------------------------------------------------------------------
  STEP 1 : IMPORT RAW DATA
  (change the DATAFILE path to wherever the xlsx is saved on your SAS server)
-------------------------------------------------------------------------*/
PROC IMPORT DATAFILE="/home/u12345678/M4_T1_V2_-_project_-_demog.xlsx"
    OUT=raw
    DBMS=XLSX
    REPLACE;
    SHEET="demog";
    GETNAMES=YES;
RUN;


/*-------------------------------------------------------------------------
  STEP 2 : DERIVE AGE, AGE GROUP AND ADD AN "ALL PATIENTS" COPY
-------------------------------------------------------------------------*/
DATA demog;
    SET raw;
    BIRTHDT = MDY(MONTH, DAY, YEAR);          /* build date of birth */
    AGE     = INT((DIAGDT - BIRTHDT)/365.25); /* age at diagnosis    */

    IF AGE < 18            THEN AGEGRP = 1;   /* <18 years      */
    ELSE IF 18 <= AGE <= 65 THEN AGEGRP = 2;   /* 18 to 65 years */
    ELSE IF AGE > 65        THEN AGEGRP = 3;   /* >65 years      */
RUN;

DATA demog_all;                 /* duplicate to build "All Patients" */
    SET demog;
    TRT = 2;
RUN;

DATA final;
    SET demog demog_all;
RUN;


/*-------------------------------------------------------------------------
  STEP 3 : FORMATS FOR LABELS
-------------------------------------------------------------------------*/
PROC FORMAT;
    VALUE trtf    0='Placebo'  1='Active Treatment'  2='All Patients';
    VALUE sexf    1='Male'     2='Female';
    VALUE racef   1='Asian'    2='African American'  3='Hispanic'
                  4='White'    5='Other';
    VALUE agegrpf 1='<18 years' 2='18 to 65 years' 3='>65 years';
RUN;

DATA final;
    SET final;
    FORMAT TRT trtf. GENDER sexf. RACE racef. AGEGRP agegrpf.;
RUN;

PROC SORT DATA=final;
    BY TRT;
RUN;


/*-------------------------------------------------------------------------
  STEP 4 : COLUMN HEADER COUNTS (N=xx per group, for the table header)
-------------------------------------------------------------------------*/
PROC SQL NOPRINT;
    SELECT COUNT(*) INTO :N_PBO  TRIMMED FROM final WHERE TRT=0;
    SELECT COUNT(*) INTO :N_ACT  TRIMMED FROM final WHERE TRT=1;
    SELECT COUNT(*) INTO :N_ALL  TRIMMED FROM final WHERE TRT=2;
QUIT;


/*-------------------------------------------------------------------------
  STEP 5 : AGE SUMMARY STATISTICS (N, MEAN, SD, MIN, MAX) BY TRT
-------------------------------------------------------------------------*/
PROC MEANS DATA=final NOPRINT;
    CLASS TRT;
    TYPES TRT;
    VAR AGE;
    OUTPUT OUT=age_stats(DROP=_TYPE_ _FREQ_)
           N=n MEAN=mean STD=std MIN=min MAX=max;
RUN;

DATA age_stats;
    SET age_stats;
    LENGTH n_c mean_c std_c min_c max_c $10;
    n_c    = strip(put(n,8.));
    mean_c = strip(put(mean,8.1));
    std_c  = strip(put(std,8.2));
    min_c  = strip(put(min,8.1));
    max_c  = strip(put(max,8.1));
RUN;

PROC TRANSPOSE DATA=age_stats OUT=age_long(RENAME=(col1=value));
    BY TRT;
    VAR n_c mean_c std_c min_c max_c;
RUN;

PROC SORT DATA=age_long;
    BY _NAME_ TRT;
RUN;

PROC TRANSPOSE DATA=age_long OUT=age_final(DROP=_NAME_) PREFIX=col;
    BY _NAME_;
    ID TRT;
    VAR value;
RUN;

DATA age_final;
    SET age_final;
    LENGTH label $20 rowlbl $20 section $12;
    section = 'Age (years)';
    IF _NAME_='n_c'    THEN DO; rowlbl='N';       order=1; END;
    IF _NAME_='mean_c' THEN DO; rowlbl='Mean';    order=2; END;
    IF _NAME_='std_c'  THEN DO; rowlbl='SD';      order=3; END;
    IF _NAME_='min_c'  THEN DO; rowlbl='Min';     order=4; END;
    IF _NAME_='max_c'  THEN DO; rowlbl='Max';     order=5; END;
RUN;


/*-------------------------------------------------------------------------
  STEP 6 : MACRO TO SUMMARIZE A CATEGORICAL VARIABLE AS "n (pct%)" BY TRT
-------------------------------------------------------------------------*/
%MACRO catvar(var=, section=, dsout=, startorder=);

    PROC FREQ DATA=final NOPRINT;
        BY TRT;
        TABLES &var / OUT=freq_&var;
    RUN;

    DATA freq_&var;
        SET freq_&var;
        LENGTH value $20;
        value = strip(put(count,8.)) || ' (' || strip(put(percent,5.1)) || '%)';
        rowlbl = vvalue(&var);
        rowsort = &var;
    RUN;

    PROC SORT DATA=freq_&var;
        BY rowsort TRT;
    RUN;

    PROC TRANSPOSE DATA=freq_&var OUT=&dsout(DROP=_NAME_) PREFIX=col;
        BY rowsort rowlbl;
        ID TRT;
        VAR value;
    RUN;

    DATA &dsout;
        SET &dsout;
        LENGTH section $20;
        section = "&section";
        order   = &startorder + rowsort;
    RUN;

%MEND catvar;

%catvar(var=AGEGRP, section=Age Groups, dsout=agegrp_final, startorder=10)
%catvar(var=GENDER,  section=Gender,     dsout=gender_final, startorder=20)
%catvar(var=RACE,    section=Race,       dsout=race_final,   startorder=30)


/*-------------------------------------------------------------------------
  STEP 7 : STACK ALL PIECES INTO ONE FINAL REPORT DATASET
-------------------------------------------------------------------------*/
DATA report_final;
    SET age_final(IN=a)
        agegrp_final(IN=b)
        gender_final(IN=c)
        race_final(IN=d);
    IF a THEN order = order;   /* order already set for age rows */
RUN;

PROC SORT DATA=report_final;
    BY order;
RUN;


/*-------------------------------------------------------------------------
  STEP 8 : PRINT THE FINAL TABLE 1.1
-------------------------------------------------------------------------*/
ODS RTF FILE="/home/u12345678/Table_1_1_Demographics.rtf" STYLE=journal;

TITLE1 "Table 1.1";
TITLE2 "Demographic and Baseline Characteristics by Treatment Group";
TITLE3 "Randomized Population";

PROC REPORT DATA=report_final NOWD HEADLINE HEADSKIP SPLIT='*';
    COLUMN section rowlbl col0 col1 col2;
    DEFINE section / GROUP NOPRINT;
    DEFINE rowlbl   / DISPLAY "  " STYLE(COLUMN)=[CELLWIDTH=2.2IN];
    DEFINE col0     / DISPLAY "Placebo*(N=&N_PBO)"           STYLE(COLUMN)=[JUST=CENTER];
    DEFINE col1     / DISPLAY "Active Treatment*(N=&N_ACT)"  STYLE(COLUMN)=[JUST=CENTER];
    DEFINE col2     / DISPLAY "All Patients*(N=&N_ALL)"      STYLE(COLUMN)=[JUST=CENTER];
    COMPUTE BEFORE section;
        LINE section $CHAR20.;
    ENDCOMP;
RUN;

FOOTNOTE1 "Note: Percentages are based on the number of non-missing values in each treatment group.";

ODS RTF CLOSE;
TITLE; FOOTNOTE;
