CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR travel RESULT result.
    METHODS accepttravel FOR MODIFY
      IMPORTING keys FOR ACTION travel~accepttravel RESULT result.

    METHODS copytravel FOR MODIFY
      IMPORTING keys FOR ACTION travel~copytravel.

    METHODS recalctotalprice FOR MODIFY
      IMPORTING keys FOR ACTION travel~recalctotalprice.

    METHODS rejecttravel FOR MODIFY
      IMPORTING keys FOR ACTION travel~rejecttravel RESULT result.
    METHODS earlynumbering_cba_booking FOR NUMBERING
      IMPORTING entities FOR CREATE travel\_booking.
    METHODS earlynumbering_create FOR NUMBERING
      IMPORTING entities FOR CREATE travel.
    METHODS get_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR travel RESULT result.
    METHODS validateagency FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validateagency.

    METHODS validatecurrencycode FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validatecurrencycode.

    METHODS validatecustomer FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validatecustomer.

    METHODS validatedates FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validatedates.

    METHODS validatestatus FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validatestatus.

ENDCLASS.

CLASS lhc_travel IMPLEMENTATION.

  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD get_features.

    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel
         FIELDS (  travel_id overall_status )
         WITH CORRESPONDING #( keys )
       RESULT DATA(travels)
       FAILED failed.


    result = VALUE #( FOR travel IN travels
                       ( %tky                           = travel-%tky
                         %features-%action-rejecttravel = COND #( WHEN travel-overall_status = 'X'
                                                                  THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled  )
                         %features-%action-accepttravel = COND #( WHEN travel-overall_status = 'A'
                                                                  THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )
                         %assoc-_booking                = COND #( WHEN travel-overall_status = 'X'
                                                                  THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )
                      ) ).

  ENDMETHOD.

  METHOD earlynumbering_create.


    DATA:
      entity        TYPE STRUCTURE FOR CREATE ziv_Travel_M,
      travel_id_max TYPE /dmo/travel_id.

    " Ensure Travel ID is not set yet (idempotent)- must be checked when BO is draft-enabled
    LOOP AT entities INTO entity WHERE travel_id IS NOT INITIAL.
      APPEND CORRESPONDING #( entity ) TO mapped-travel.
    ENDLOOP.

    DATA(entities_wo_travelid) = entities.
    DELETE entities_wo_travelid WHERE travel_id IS NOT INITIAL.

    " Get Numbers
    TRY.
        cl_numberrange_runtime=>number_get(
          EXPORTING
            nr_range_nr       = '01'
            object            = '/DMO/TRV_M'
            quantity          = CONV #( lines( entities_wo_travelid ) )
          IMPORTING
            number            = DATA(number_range_key)
            returncode        = DATA(number_range_return_code)
            returned_quantity = DATA(number_range_returned_quantity)
        ).
      CATCH cx_number_ranges INTO DATA(lx_number_ranges).
        LOOP AT entities_wo_travelid INTO entity.
          APPEND VALUE #(  %cid = entity-%cid
                           %key = entity-%key
                           %msg = lx_number_ranges
                        ) TO reported-travel.
          APPEND VALUE #(  %cid = entity-%cid
                           %key = entity-%key
                        ) TO failed-travel.
        ENDLOOP.
        EXIT.
    ENDTRY.

    CASE number_range_return_code.
      WHEN '1'.
        " 1 - the returned number is in a critical range (specified under “percentage warning” in the object definition)
        LOOP AT entities_wo_travelid INTO entity.
          APPEND VALUE #( %cid = entity-%cid
                          %key = entity-%key
                          %msg = NEW /dmo/cm_flight_messages(
                                      textid = /dmo/cm_flight_messages=>number_range_depleted
                                      severity = if_abap_behv_message=>severity-warning )
                        ) TO reported-travel.
        ENDLOOP.

      WHEN '2' OR '3'.
        " 2 - the last number of the interval was returned
        " 3 - if fewer numbers are available than requested,  the return code is 3
        LOOP AT entities_wo_travelid INTO entity.
          APPEND VALUE #( %cid = entity-%cid
                          %key = entity-%key
                          %msg = NEW /dmo/cm_flight_messages(
                                      textid = /dmo/cm_flight_messages=>not_sufficient_numbers
                                      severity = if_abap_behv_message=>severity-warning )
                        ) TO reported-travel.
          APPEND VALUE #( %cid        = entity-%cid
                          %key        = entity-%key
                          %fail-cause = if_abap_behv=>cause-conflict
                        ) TO failed-travel.
        ENDLOOP.
        EXIT.
    ENDCASE.

    " At this point ALL entities get a number!
    ASSERT number_range_returned_quantity = lines( entities_wo_travelid ).

    travel_id_max = number_range_key - number_range_returned_quantity.

    " Set Travel ID
    LOOP AT entities_wo_travelid INTO entity.
      travel_id_max += 1.
      entity-travel_id = travel_id_max .

      APPEND VALUE #( %cid  = entity-%cid
                      %key  = entity-%key
                    ) TO mapped-travel.
    ENDLOOP.

  ENDMETHOD.

  METHOD earlynumbering_cba_Booking.

    DATA: max_booking_id TYPE /dmo/booking_id.

    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel BY \_booking
        FROM CORRESPONDING #( entities )
        LINK DATA(bookings).

    " Loop over all unique TravelIDs
    LOOP AT entities ASSIGNING FIELD-SYMBOL(<travel_group>) GROUP BY <travel_group>-travel_id.

      " Get highest booking_id from bookings belonging to travel
      max_booking_id = REDUCE #( INIT max = CONV /dmo/booking_id( '0' )
                                 FOR  booking IN bookings USING KEY entity WHERE ( source-travel_id  = <travel_group>-travel_id )
                                 NEXT max = COND /dmo/booking_id( WHEN booking-target-booking_id > max
                                                                    THEN booking-target-booking_id
                                                                    ELSE max )
                               ).
      " Get highest assigned booking_id from incoming entities
      max_booking_id = REDUCE #( INIT max = max_booking_id
                                 FOR  entity IN entities USING KEY entity WHERE ( travel_id  = <travel_group>-travel_id )
                                 FOR  target IN entity-%target
                                 NEXT max = COND /dmo/booking_id( WHEN   target-booking_id > max
                                                                    THEN target-booking_id
                                                                    ELSE max )
                               ).

      " Loop over all entries in entities with the same TravelID
      LOOP AT entities ASSIGNING FIELD-SYMBOL(<travel>) USING KEY entity WHERE travel_id = <travel_group>-travel_id.

        " Assign new booking-ids if not already assigned
        LOOP AT <travel>-%target ASSIGNING FIELD-SYMBOL(<booking_wo_numbers>).
          APPEND CORRESPONDING #( <booking_wo_numbers> ) TO mapped-booking ASSIGNING FIELD-SYMBOL(<mapped_booking>).
          IF <booking_wo_numbers>-booking_id IS INITIAL.
            max_booking_id += 10 .
            <mapped_booking>-booking_id = max_booking_id .
          ENDIF.
        ENDLOOP.

      ENDLOOP.

    ENDLOOP.

  ENDMETHOD.

  METHOD acceptTravel.


    " Modify in local mode: BO-related updates that are not relevant for authorization checks
    MODIFY ENTITIES OF ziv_Travel_M IN LOCAL MODE
           ENTITY travel
              UPDATE FIELDS ( overall_status )
                 WITH VALUE #( FOR key IN keys ( %tky      = key-%tky
                                                 overall_status = 'A' ) ). " Accepted

    " Read changed data for action result
    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel
         ALL FIELDS WITH
         CORRESPONDING #( keys )
       RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels ( %tky      = travel-%tky
                                              %param    = travel ) ).

  ENDMETHOD.

  METHOD copyTravel.

    DATA:
      travels       TYPE TABLE FOR CREATE ziv_Travel_M\\travel,
      bookings_cba  TYPE TABLE FOR CREATE ziv_Travel_M\\travel\_booking,
      booksuppl_cba TYPE TABLE FOR CREATE ziv_Travel_M\\booking\_booksupplement.

    READ TABLE keys WITH KEY %cid = '' INTO DATA(key_with_inital_cid).
    ASSERT key_with_inital_cid IS INITIAL.

    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel
       ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travel_read_result)
    FAILED failed.

    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel BY \_booking
       ALL FIELDS WITH CORRESPONDING #( travel_read_result )
     RESULT DATA(book_read_result).

    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY booking BY \_booksupplement
       ALL FIELDS WITH CORRESPONDING #( book_read_result )
    RESULT DATA(booksuppl_read_result).

    LOOP AT travel_read_result ASSIGNING FIELD-SYMBOL(<travel>).
      "Fill travel container for creating new travel instance
      APPEND VALUE #( %cid     = keys[ KEY entity %tky = <travel>-%tky ]-%cid
                      %data    = CORRESPONDING #( <travel> EXCEPT travel_id ) )
        TO travels ASSIGNING FIELD-SYMBOL(<new_travel>).

      "Fill %cid_ref of travel as instance identifier for cba booking
      APPEND VALUE #( %cid_ref = keys[ KEY entity %tky = <travel>-%tky ]-%cid )
        TO bookings_cba ASSIGNING FIELD-SYMBOL(<bookings_cba>).

      <new_travel>-begin_date     = cl_abap_context_info=>get_system_date( ).
      <new_travel>-end_date       = cl_abap_context_info=>get_system_date( ) + 30.
      <new_travel>-overall_status = 'O'.  "Set to open to allow an editable instance

      LOOP AT book_read_result ASSIGNING FIELD-SYMBOL(<booking>) USING KEY entity WHERE travel_id EQ <travel>-travel_id.
        "Fill booking container for creating booking with cba
        APPEND VALUE #( %cid     = keys[ KEY entity %tky = <travel>-%tky ]-%cid && <booking>-booking_id
                        %data    = CORRESPONDING #(  book_read_result[ KEY entity %tky = <booking>-%tky ] EXCEPT travel_id ) )
          TO <bookings_cba>-%target ASSIGNING FIELD-SYMBOL(<new_booking>).

        "Fill %cid_ref of booking as instance identifier for cba booksuppl
        APPEND VALUE #( %cid_ref = keys[ KEY entity %tky = <travel>-%tky ]-%cid && <booking>-booking_id )
          TO booksuppl_cba ASSIGNING FIELD-SYMBOL(<booksuppl_cba>).

        <new_booking>-booking_status = 'N'.

        LOOP AT booksuppl_read_result ASSIGNING FIELD-SYMBOL(<booksuppl>) USING KEY entity WHERE travel_id  EQ <travel>-travel_id
                                                                                           AND   booking_id EQ <booking>-booking_id.
          "Fill booksuppl container for creating supplement with cba
          APPEND VALUE #( %cid  = keys[ KEY entity %tky = <travel>-%tky ]-%cid  && <booking>-booking_id && <booksuppl>-booking_supplement_id
                          %data = CORRESPONDING #( <booksuppl> EXCEPT travel_id booking_id ) )
            TO <booksuppl_cba>-%target.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    "create new BO instance
    MODIFY ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel
        CREATE FIELDS ( agency_id customer_id begin_date end_date booking_fee total_price currency_code overall_status description )
          WITH travels
        CREATE BY \_Booking FIELDS ( booking_id booking_date customer_id carrier_id connection_id flight_date flight_price currency_code booking_status )
          WITH bookings_cba
      ENTITY booking
        CREATE BY \_BookSupplement FIELDS ( booking_supplement_id supplement_id price currency_code )
          WITH booksuppl_cba
      MAPPED DATA(mapped_create).

    mapped-travel   =  mapped_create-travel .

  ENDMETHOD.

  METHOD ReCalcTotalPrice.

 TYPES: BEGIN OF ty_amount_per_currencycode,
             amount        TYPE /dmo/total_price,
             currency_code TYPE /dmo/currency_code,
           END OF ty_amount_per_currencycode.

    DATA: amounts_per_currencycode TYPE STANDARD TABLE OF ty_amount_per_currencycode.

    " Read all relevant travel instances.
    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
         ENTITY travel
            FIELDS ( booking_fee currency_code )
            WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    DELETE travels WHERE currency_code IS INITIAL.

    " Read all associated bookings and add them to the total price.
    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel BY \_booking
        FIELDS ( flight_price currency_code )
      WITH CORRESPONDING #( travels )
      RESULT DATA(bookings).

    " Read all associated booking supplements and add them to the total price.
    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY booking BY \_booksupplement
        FIELDS ( price currency_code )
      WITH CORRESPONDING #( bookings )
      RESULT DATA(bookingsupplements).

    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).
      " Set the start for the calculation by adding the booking fee.
      amounts_per_currencycode = VALUE #( ( amount        = <travel>-booking_fee
                                           currency_code = <travel>-currency_code ) ).


      LOOP AT bookings INTO DATA(booking) USING KEY id WHERE   travel_id = <travel>-travel_id
                                                       AND     currency_code IS NOT INITIAL.
        COLLECT VALUE ty_amount_per_currencycode( amount        = booking-flight_price
                                                  currency_code = booking-currency_code
                                                ) INTO amounts_per_currencycode.
      ENDLOOP.


      LOOP AT bookingsupplements INTO DATA(bookingsupplement) USING KEY id WHERE   travel_id = <travel>-travel_id
                                                                           AND     currency_code IS NOT INITIAL.
        COLLECT VALUE ty_amount_per_currencycode( amount        = bookingsupplement-price
                                                  currency_code = bookingsupplement-currency_code
                                                ) INTO amounts_per_currencycode.
      ENDLOOP.

      DELETE amounts_per_currencycode WHERE currency_code IS INITIAL.

      CLEAR <travel>-total_price.
      LOOP AT amounts_per_currencycode INTO DATA(amount_per_currencycode).
        " If needed do a Currency Conversion
        IF amount_per_currencycode-currency_code = <travel>-currency_code.
          <travel>-total_price += amount_per_currencycode-amount.
        ELSE.
          /dmo/cl_flight_amdp=>convert_currency(
             EXPORTING
               iv_amount                   =  amount_per_currencycode-amount
               iv_currency_code_source     =  amount_per_currencycode-currency_code
               iv_currency_code_target     =  <travel>-currency_code
               iv_exchange_rate_date       =  cl_abap_context_info=>get_system_date( )
             IMPORTING
               ev_amount                   = DATA(total_booking_price_per_curr)
            ).
          <travel>-total_price += total_booking_price_per_curr.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " write back the modified total_price of travels
    MODIFY ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel
        UPDATE FIELDS ( total_price )
        WITH CORRESPONDING #( travels ).

  ENDMETHOD.

  METHOD rejectTravel.

    " Modify in local mode: BO-related updates that are not relevant for authorization checks
    MODIFY ENTITIES OF ziv_Travel_M IN LOCAL MODE
           ENTITY travel
              UPDATE FIELDS ( overall_status )
                 WITH VALUE #( FOR key IN keys ( %tky      = key-%tky
                                                 overall_status = 'X' ) ). " Rejected

    " Read changed data for action result
    READ ENTITIES OF ziv_Travel_M IN LOCAL MODE
      ENTITY travel
         ALL FIELDS WITH
         CORRESPONDING #( keys )
       RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels ( %tky      = travel-%tky
                                              %param    = travel ) ).

  ENDMETHOD.

  METHOD validateAgency.
  ENDMETHOD.

  METHOD validateCurrencyCode.
  ENDMETHOD.

  METHOD validateCustomer.
  ENDMETHOD.

  METHOD validateDates.
  ENDMETHOD.

  METHOD validateStatus.
  ENDMETHOD.

ENDCLASS.
