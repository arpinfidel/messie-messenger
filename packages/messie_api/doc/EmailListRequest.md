# messie_api.model.EmailListRequest

## Load the model package
```dart
import 'package:messie_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**host** | **String** |  | 
**port** | **int** |  | 
**email** | **String** |  | 
**appPassword** | **String** |  | 
**mailbox** | **String** | Mailbox name to select (defaults to INBOX when omitted) | [optional] 
**searchFlags** | **BuiltList&lt;String&gt;** | Optional IMAP flags to filter on (e.g. [\"\\\\Flagged\"]) | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


