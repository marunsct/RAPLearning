@EndUserText.label: 'Projection View Carrier'
@AccessControl.authorizationCheck: #NOT_REQUIRED

@Metadata.allowExtensions: true
@ObjectModel.semanticKey: ['AirlineID']


define view entity ZCV_Carrier_S
  as projection on ZIV_Carrier_S
{
  key AirlineID,
  
      @Consumption.hidden: true
      CarrierSingletonID,
      
      Name,
      
      @Consumption.valueHelpDefinition: [{entity: {name: 'I_Currency', element: 'Currency' }, useForValidation: true }]
      CurrencyCode,
      
      LocalLastChangedAt,
      
      /* Associations */
      _CarrierSingleton : redirected to parent ZCV_CarriersLockSingleton_S
}
