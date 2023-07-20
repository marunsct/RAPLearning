FUNCTION ZFLIGHT_BOOKSUPPL_U.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(VALUES) TYPE  ZTT_BOOKSUPPL_M
*"----------------------------------------------------------------------

  UPDATE zbooksuppl_m FROM TABLE @values.






ENDFUNCTION.
