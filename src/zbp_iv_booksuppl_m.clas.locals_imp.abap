CLASS lhc_bookingsuppl DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS calculateTotalPrice FOR DETERMINE ON MODIFY
      IMPORTING keys FOR bookingsuppl~calculateTotalPrice.

ENDCLASS.

CLASS lhc_bookingsuppl IMPLEMENTATION.

  METHOD calculateTotalPrice.
    DATA: travel_ids TYPE STANDARD TABLE OF ziv_travel_m WITH UNIQUE HASHED KEY key COMPONENTS travel_id.

    travel_ids = CORRESPONDING #( keys DISCARDING DUPLICATES MAPPING travel_id = travel_id ).

    MODIFY ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY Travel
        EXECUTE ReCalcTotalPrice
        FROM CORRESPONDING #( travel_ids ).
  ENDMETHOD.

ENDCLASS.

*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type
*"* declarations
