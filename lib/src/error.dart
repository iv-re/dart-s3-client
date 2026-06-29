import 'package:s3_client/src/model.dart';

/// S3 base exception class.
abstract class S3Exception implements Exception {
  const S3Exception({
    required this.code,
    required this.message,
  });

  factory S3Exception.fromError(S3Error error) {
    return S3Exception.fromCode(error.code, error.message);
  }

  factory S3Exception.fromCode(String code, String message) {
    return switch (code) {
      'AccessDenied' => S3AccessDeniedException(message),
      'AccountProblem' => S3AccountProblemException(message),
      'AllAccessDisabled' => S3AllAccessDisabledException(message),
      'AmbiguousGrantByEmailAddress' => S3AmbiguousGrantByEmailAddressException(
        message,
      ),
      'AuthorizationHeaderMalformed' => S3AuthorizationHeaderMalformedException(
        message,
      ),
      'BadDigest' => S3BadDigestException(message),
      'BucketAlreadyExists' => S3BucketAlreadyExistsException(message),
      'BucketAlreadyOwnedByYou' => S3BucketAlreadyOwnedByYouException(message),
      'BucketNotEmpty' => S3BucketNotEmptyException(message),
      'CredentialsNotSupported' => S3CredentialsNotSupportedException(message),
      'CrossLocationLoggingProhibited' =>
        S3CrossLocationLoggingProhibitedException(message),
      'EntityTooSmall' => S3EntityTooSmallException(message),
      'EntityTooLarge' => S3EntityTooLargeException(message),
      'ExpiredToken' => S3ExpiredTokenException(message),
      'IllegalVersioningConfigurationException' =>
        S3IllegalVersioningConfigurationException(message),
      'IncompleteBody' => S3IncompleteBodyException(message),
      'IncorrectNumberOfFilesInPostRequest' =>
        S3IncorrectNumberOfFilesInPostRequestException(message),
      'InlineDataTooLarge' => S3InlineDataTooLargeException(message),
      'InternalError' => S3InternalErrorException(message),
      'InvalidAccessKeyId' => S3InvalidAccessKeyIdException(message),
      'InvalidAddressingHeader' => S3InvalidAddressingHeaderException(message),
      'InvalidArgument' => S3InvalidArgumentException(message),
      'InvalidBucketName' => S3InvalidBucketNameException(message),
      'InvalidBucketState' => S3InvalidBucketStateException(message),
      'InvalidDigest' => S3InvalidDigestException(message),
      'InvalidEncryptionAlgorithmError' =>
        S3InvalidEncryptionAlgorithmException(message),
      'InvalidLocationConstraint' => S3InvalidLocationConstraintException(
        message,
      ),
      'InvalidObjectState' => S3InvalidObjectStateException(message),
      'InvalidPart' => S3InvalidPartException(message),
      'InvalidPartOrder' => S3InvalidPartOrderException(message),
      'InvalidPayer' => S3InvalidPayerException(message),
      'InvalidPolicyDocument' => S3InvalidPolicyDocumentException(message),
      'InvalidRange' => S3InvalidRangeException(message),
      'InvalidRequest' => S3InvalidRequestException(message),
      'InvalidSecurity' => S3InvalidSecurityException(message),
      'InvalidSOAPRequest' => S3InvalidSOAPRequestException(message),
      'InvalidStorageClass' => S3InvalidStorageClassException(message),
      'InvalidTargetBucketForLogging' =>
        S3InvalidTargetBucketForLoggingException(message),
      'InvalidToken' => S3InvalidTokenException(message),
      'InvalidURI' => S3InvalidURIException(message),
      'KeyTooLongError' => S3KeyTooLongException(message),
      'MalformedACLError' => S3MalformedACLException(message),
      'MalformedPOSTRequest' => S3MalformedPOSTRequestException(message),
      'MalformedXML' => S3MalformedXMLException(message),
      'MaxMessageLengthExceeded' => S3MaxMessageLengthExceededException(
        message,
      ),
      'MaxPostPreDataLengthExceededError' => S3MaxPostPreDataLengthException(
        message,
      ),
      'MetadataTooLarge' => S3MetadataTooLargeException(message),
      'MethodNotAllowed' => S3MethodNotAllowedException(message),
      'MissingAttachment' => S3MissingAttachmentException(message),
      'MissingContentLength' => S3MissingContentLengthException(message),
      'MissingRequestBodyError' => S3MissingRequestBodyException(message),
      'MissingSecurityElement' => S3MissingSecurityElementException(message),
      'MissingSecurityHeader' => S3MissingSecurityHeaderException(message),
      'NoLoggingStatusForKey' => S3NoLoggingStatusForKeyException(message),
      'NoSuchBucket' => S3NoSuchBucketException(message),
      'NoSuchBucketPolicy' => S3NoSuchBucketPolicyException(message),
      'NoSuchKey' => S3NoSuchKeyException(message),
      'NoSuchLifecycleConfiguration' => S3NoSuchLifecycleConfigurationException(
        message,
      ),
      'NoSuchUpload' => S3NoSuchUploadException(message),
      'NoSuchVersion' => S3NoSuchVersionException(message),
      'NotImplemented' => S3NotImplementedException(message),
      'NotSignedUp' => S3NotSignedUpException(message),
      'OperationAborted' => S3OperationAbortedException(message),
      'PermanentRedirect' => S3PermanentRedirectException(message),
      'PreconditionFailed' => S3PreconditionFailedException(message),
      'Redirect' => S3RedirectException(message),
      'RestoreAlreadyInProgress' => S3RestoreAlreadyInProgressException(
        message,
      ),
      'RequestIsNotMultiPartContent' => S3RequestIsNotMultiPartContentException(
        message,
      ),
      'RequestTimeout' => S3RequestTimeoutException(message),
      'RequestTimeTooSkewed' => S3RequestTimeTooSkewedException(message),
      'RequestTorrentOfBucketError' => S3RequestTorrentOfBucketException(
        message,
      ),
      'SignatureDoesNotMatch' => S3SignatureDoesNotMatchException(message),
      'ServiceUnavailable' => S3ServiceUnavailableException(message),
      'SlowDown' => S3SlowDownException(message),
      'TemporaryRedirect' => S3TemporaryRedirectException(message),
      'TokenRefreshRequired' => S3TokenRefreshRequiredException(message),
      'TooManyBuckets' => S3TooManyBucketsException(message),
      'UnexpectedContent' => S3UnexpectedContentException(message),
      'UnresolvableGrantByEmailAddress' =>
        S3UnresolvableGrantByEmailAddressException(message),
      'UserKeyMustBeSpecified' => S3UserKeyMustBeSpecifiedException(message),
      _ => S3UnknownException(code, message),
    };
  }

  final String code;
  final String message;

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';
}

class S3UnknownException extends S3Exception {
  const S3UnknownException(String code, String message)
    : super(code: code, message: message);
}

/// Access Denied
class S3AccessDeniedException extends S3Exception {
  const S3AccessDeniedException(String message)
    : super(code: 'AccessDenied', message: message);
}

/// There is a problem with your AWS account that prevents the action from
/// completing successfully. Contact AWS Support for further assistance.
class S3AccountProblemException extends S3Exception {
  const S3AccountProblemException(String message)
    : super(code: 'AccountProblem', message: message);
}

/// All access to this Amazon S3 resource has been disabled. Contact AWS
/// Support for further assistance.
class S3AllAccessDisabledException extends S3Exception {
  const S3AllAccessDisabledException(String message)
    : super(code: 'AllAccessDisabled', message: message);
}

/// The email address you provided is associated with more than one account.
class S3AmbiguousGrantByEmailAddressException extends S3Exception {
  const S3AmbiguousGrantByEmailAddressException(String message)
    : super(code: 'AmbiguousGrantByEmailAddress', message: message);
}

/// The authorization header you provided is invalid.
class S3AuthorizationHeaderMalformedException extends S3Exception {
  const S3AuthorizationHeaderMalformedException(String message)
    : super(code: 'AuthorizationHeaderMalformed', message: message);
}

/// The Content-MD5 you specified did not match what we received.
class S3BadDigestException extends S3Exception {
  const S3BadDigestException(String message)
    : super(code: 'BadDigest', message: message);
}

/// The requested bucket name is not available. The bucket namespace is
/// shared by all users of the system. Please select a different name and
/// try again.
class S3BucketAlreadyExistsException extends S3Exception {
  const S3BucketAlreadyExistsException(String message)
    : super(code: 'BucketAlreadyExists', message: message);
}

/// The bucket you tried to create already exists, and you own it. Amazon S3
/// returns this error in all AWS Regions except in the North Virginia
/// Region. For legacy compatibility, if you re-create an existing bucket
/// that you already own in the North Virginia Region, Amazon S3 returns
/// 200 OK and resets the bucket access control lists (ACLs).
class S3BucketAlreadyOwnedByYouException extends S3Exception {
  const S3BucketAlreadyOwnedByYouException(String message)
    : super(code: 'BucketAlreadyOwnedByYou', message: message);
}

/// The bucket you tried to delete is not empty.
class S3BucketNotEmptyException extends S3Exception {
  const S3BucketNotEmptyException(String message)
    : super(code: 'BucketNotEmpty', message: message);
}

/// This request does not support credentials.
class S3CredentialsNotSupportedException extends S3Exception {
  const S3CredentialsNotSupportedException(String message)
    : super(code: 'CredentialsNotSupported', message: message);
}

/// Cross-location logging not allowed. Buckets in one geographic location
/// cannot log information to a bucket in another location.
class S3CrossLocationLoggingProhibitedException extends S3Exception {
  const S3CrossLocationLoggingProhibitedException(String message)
    : super(code: 'CrossLocationLoggingProhibited', message: message);
}

/// Your proposed upload is smaller than the minimum allowed object size.
class S3EntityTooSmallException extends S3Exception {
  const S3EntityTooSmallException(String message)
    : super(code: 'EntityTooSmall', message: message);
}

/// Your proposed upload exceeds the maximum allowed object size.
class S3EntityTooLargeException extends S3Exception {
  const S3EntityTooLargeException(String message)
    : super(code: 'EntityTooLarge', message: message);
}

/// The provided token has expired.
class S3ExpiredTokenException extends S3Exception {
  const S3ExpiredTokenException(String message)
    : super(code: 'ExpiredToken', message: message);
}

/// Indicates that the versioning configuration specified in the request is
/// invalid.
class S3IllegalVersioningConfigurationException extends S3Exception {
  const S3IllegalVersioningConfigurationException(String message)
    : super(code: 'IllegalVersioningConfigurationException', message: message);
}

/// You did not provide the number of bytes specified by the Content-Length
/// HTTP header
class S3IncompleteBodyException extends S3Exception {
  const S3IncompleteBodyException(String message)
    : super(code: 'IncompleteBody', message: message);
}

/// POST requires exactly one file upload per request.
class S3IncorrectNumberOfFilesInPostRequestException extends S3Exception {
  const S3IncorrectNumberOfFilesInPostRequestException(String message)
    : super(code: 'IncorrectNumberOfFilesInPostRequest', message: message);
}

/// Inline data exceeds the maximum allowed size.
class S3InlineDataTooLargeException extends S3Exception {
  const S3InlineDataTooLargeException(String message)
    : super(code: 'InlineDataTooLarge', message: message);
}

/// We encountered an internal error. Please try again.
class S3InternalErrorException extends S3Exception {
  const S3InternalErrorException(String message)
    : super(code: 'InternalError', message: message);
}

/// The AWS access key ID you provided does not exist in our records.
class S3InvalidAccessKeyIdException extends S3Exception {
  const S3InvalidAccessKeyIdException(String message)
    : super(code: 'InvalidAccessKeyId', message: message);
}

/// You must specify the Anonymous role.
class S3InvalidAddressingHeaderException extends S3Exception {
  const S3InvalidAddressingHeaderException(String message)
    : super(code: 'InvalidAddressingHeader', message: message);
}

/// Invalid Argument
class S3InvalidArgumentException extends S3Exception {
  const S3InvalidArgumentException(String message)
    : super(code: 'InvalidArgument', message: message);
}

/// The specified bucket is not valid.
class S3InvalidBucketNameException extends S3Exception {
  const S3InvalidBucketNameException(String message)
    : super(code: 'InvalidBucketName', message: message);
}

/// The request is not valid with the current state of the bucket.
class S3InvalidBucketStateException extends S3Exception {
  const S3InvalidBucketStateException(String message)
    : super(code: 'InvalidBucketState', message: message);
}

/// The Content-MD5 you specified is not valid.
class S3InvalidDigestException extends S3Exception {
  const S3InvalidDigestException(String message)
    : super(code: 'InvalidDigest', message: message);
}

/// The encryption request you specified is not valid. The valid value is
/// AES256.
class S3InvalidEncryptionAlgorithmException extends S3Exception {
  const S3InvalidEncryptionAlgorithmException(String message)
    : super(code: 'InvalidEncryptionAlgorithmError', message: message);
}

/// The specified location constraint is not valid.
class S3InvalidLocationConstraintException extends S3Exception {
  const S3InvalidLocationConstraintException(String message)
    : super(code: 'InvalidLocationConstraint', message: message);
}

/// The action is not valid for the current state of the object.
class S3InvalidObjectStateException extends S3Exception {
  const S3InvalidObjectStateException(String message)
    : super(code: 'InvalidObjectState', message: message);
}

/// One or more of the specified parts could not be found. The part might
/// not have been uploaded, or the specified entity tag might not have
/// matched the part's entity tag.
class S3InvalidPartException extends S3Exception {
  const S3InvalidPartException(String message)
    : super(code: 'InvalidPart', message: message);
}

/// The list of parts was not in ascending order. Parts list must be
/// specified in order by part number.
class S3InvalidPartOrderException extends S3Exception {
  const S3InvalidPartOrderException(String message)
    : super(code: 'InvalidPartOrder', message: message);
}

/// All access to this object has been disabled. Please contact AWS Support
/// for further assistance.
class S3InvalidPayerException extends S3Exception {
  const S3InvalidPayerException(String message)
    : super(code: 'InvalidPayer', message: message);
}

/// The content of the form does not meet the conditions specified in the
/// policy document.
class S3InvalidPolicyDocumentException extends S3Exception {
  const S3InvalidPolicyDocumentException(String message)
    : super(code: 'InvalidPolicyDocument', message: message);
}

/// The requested range cannot be satisfied.
class S3InvalidRangeException extends S3Exception {
  const S3InvalidRangeException(String message)
    : super(code: 'InvalidRange', message: message);
}

/// Please use AWS4-HMAC-SHA256, or SOAP requests must be made over an HTTPS
/// connection, or other invalid requests.
class S3InvalidRequestException extends S3Exception {
  const S3InvalidRequestException(String message)
    : super(code: 'InvalidRequest', message: message);
}

/// The provided security credentials are not valid.
class S3InvalidSecurityException extends S3Exception {
  const S3InvalidSecurityException(String message)
    : super(code: 'InvalidSecurity', message: message);
}

/// The SOAP request body is invalid.
class S3InvalidSOAPRequestException extends S3Exception {
  const S3InvalidSOAPRequestException(String message)
    : super(code: 'InvalidSOAPRequest', message: message);
}

/// The storage class you specified is not valid.
class S3InvalidStorageClassException extends S3Exception {
  const S3InvalidStorageClassException(String message)
    : super(code: 'InvalidStorageClass', message: message);
}

/// The target bucket for logging does not exist, is not owned by you, or
/// does not have the appropriate grants for the log-delivery group.
class S3InvalidTargetBucketForLoggingException extends S3Exception {
  const S3InvalidTargetBucketForLoggingException(String message)
    : super(code: 'InvalidTargetBucketForLogging', message: message);
}

/// The provided token is malformed or otherwise invalid.
class S3InvalidTokenException extends S3Exception {
  const S3InvalidTokenException(String message)
    : super(code: 'InvalidToken', message: message);
}

/// Couldn't parse the specified URI.
class S3InvalidURIException extends S3Exception {
  const S3InvalidURIException(String message)
    : super(code: 'InvalidURI', message: message);
}

/// Your key is too long.
class S3KeyTooLongException extends S3Exception {
  const S3KeyTooLongException(String message)
    : super(code: 'KeyTooLongError', message: message);
}

/// The XML you provided was not well-formed or did not validate against our
/// published schema.
class S3MalformedACLException extends S3Exception {
  const S3MalformedACLException(String message)
    : super(code: 'MalformedACLError', message: message);
}

/// The body of your POST request is not well-formed multipart/form-data.
class S3MalformedPOSTRequestException extends S3Exception {
  const S3MalformedPOSTRequestException(String message)
    : super(code: 'MalformedPOSTRequest', message: message);
}

/// This happens when the user sends malformed XML (XML that doesn't conform
/// to the published XSD) for the configuration.
class S3MalformedXMLException extends S3Exception {
  const S3MalformedXMLException(String message)
    : super(code: 'MalformedXML', message: message);
}

/// Your request was too big.
class S3MaxMessageLengthExceededException extends S3Exception {
  const S3MaxMessageLengthExceededException(String message)
    : super(code: 'MaxMessageLengthExceeded', message: message);
}

/// Your POST request fields preceding the upload file were too large.
class S3MaxPostPreDataLengthException extends S3Exception {
  const S3MaxPostPreDataLengthException(String message)
    : super(code: 'MaxPostPreDataLengthExceededError', message: message);
}

/// Your metadata headers exceed the maximum allowed metadata size.
class S3MetadataTooLargeException extends S3Exception {
  const S3MetadataTooLargeException(String message)
    : super(code: 'MetadataTooLarge', message: message);
}

/// The specified method is not allowed against this resource.
class S3MethodNotAllowedException extends S3Exception {
  const S3MethodNotAllowedException(String message)
    : super(code: 'MethodNotAllowed', message: message);
}

/// A SOAP attachment was expected, but none were found.
class S3MissingAttachmentException extends S3Exception {
  const S3MissingAttachmentException(String message)
    : super(code: 'MissingAttachment', message: message);
}

/// You must provide the Content-Length HTTP header.
class S3MissingContentLengthException extends S3Exception {
  const S3MissingContentLengthException(String message)
    : super(code: 'MissingContentLength', message: message);
}

/// Request body is empty.
class S3MissingRequestBodyException extends S3Exception {
  const S3MissingRequestBodyException(String message)
    : super(code: 'MissingRequestBodyError', message: message);
}

/// The SOAP 1.1 request is missing a security element.
class S3MissingSecurityElementException extends S3Exception {
  const S3MissingSecurityElementException(String message)
    : super(code: 'MissingSecurityElement', message: message);
}

/// Your request is missing a required header.
class S3MissingSecurityHeaderException extends S3Exception {
  const S3MissingSecurityHeaderException(String message)
    : super(code: 'MissingSecurityHeader', message: message);
}

/// There is no such thing as a logging status subresource for a key.
class S3NoLoggingStatusForKeyException extends S3Exception {
  const S3NoLoggingStatusForKeyException(String message)
    : super(code: 'NoLoggingStatusForKey', message: message);
}

/// The specified bucket does not exist.
class S3NoSuchBucketException extends S3Exception {
  const S3NoSuchBucketException(String message)
    : super(code: 'NoSuchBucket', message: message);
}

/// The specified bucket does not have a bucket policy.
class S3NoSuchBucketPolicyException extends S3Exception {
  const S3NoSuchBucketPolicyException(String message)
    : super(code: 'NoSuchBucketPolicy', message: message);
}

/// The specified key does not exist.
class S3NoSuchKeyException extends S3Exception {
  const S3NoSuchKeyException(String message)
    : super(code: 'NoSuchKey', message: message);
}

/// The lifecycle configuration does not exist.
class S3NoSuchLifecycleConfigurationException extends S3Exception {
  const S3NoSuchLifecycleConfigurationException(String message)
    : super(code: 'NoSuchLifecycleConfiguration', message: message);
}

/// The specified multipart upload does not exist. The upload ID might be
/// invalid, or the multipart upload might have been aborted or completed.
class S3NoSuchUploadException extends S3Exception {
  const S3NoSuchUploadException(String message)
    : super(code: 'NoSuchUpload', message: message);
}

/// Indicates that the version ID specified in the request does not match an
/// existing version.
class S3NoSuchVersionException extends S3Exception {
  const S3NoSuchVersionException(String message)
    : super(code: 'NoSuchVersion', message: message);
}

/// A header you provided implies functionality that is not implemented.
class S3NotImplementedException extends S3Exception {
  const S3NotImplementedException(String message)
    : super(code: 'NotImplemented', message: message);
}

/// Your account is not signed up for the Amazon S3 service.
class S3NotSignedUpException extends S3Exception {
  const S3NotSignedUpException(String message)
    : super(code: 'NotSignedUp', message: message);
}

/// A conflicting conditional action is currently in progress against this
/// resource. Try again.
class S3OperationAbortedException extends S3Exception {
  const S3OperationAbortedException(String message)
    : super(code: 'OperationAborted', message: message);
}

/// The bucket you are attempting to access must be addressed using the
/// specified endpoint. Send all future requests to this endpoint.
class S3PermanentRedirectException extends S3Exception {
  const S3PermanentRedirectException(String message)
    : super(code: 'PermanentRedirect', message: message);
}

/// At least one of the preconditions you specified did not hold.
class S3PreconditionFailedException extends S3Exception {
  const S3PreconditionFailedException(String message)
    : super(code: 'PreconditionFailed', message: message);
}

/// Temporary redirect.
class S3RedirectException extends S3Exception {
  const S3RedirectException(String message)
    : super(code: 'Redirect', message: message);
}

/// Object restore is already in progress.
class S3RestoreAlreadyInProgressException extends S3Exception {
  const S3RestoreAlreadyInProgressException(String message)
    : super(code: 'RestoreAlreadyInProgress', message: message);
}

/// Bucket POST must be of the enclosure-type multipart/form-data.
class S3RequestIsNotMultiPartContentException extends S3Exception {
  const S3RequestIsNotMultiPartContentException(String message)
    : super(code: 'RequestIsNotMultiPartContent', message: message);
}

/// Your socket connection to the server was not read from or written to within
/// the timeout period.
class S3RequestTimeoutException extends S3Exception {
  const S3RequestTimeoutException(String message)
    : super(code: 'RequestTimeout', message: message);
}

/// The difference between the request time and the server's time is too
/// large.
class S3RequestTimeTooSkewedException extends S3Exception {
  const S3RequestTimeTooSkewedException(String message)
    : super(code: 'RequestTimeTooSkewed', message: message);
}

/// Requesting the torrent file of a bucket is not permitted.
class S3RequestTorrentOfBucketException extends S3Exception {
  const S3RequestTorrentOfBucketException(String message)
    : super(code: 'RequestTorrentOfBucketError', message: message);
}

/// The request signature we calculated does not match the signature you
/// provided. Check your AWS secret access key and signing method.
class S3SignatureDoesNotMatchException extends S3Exception {
  const S3SignatureDoesNotMatchException(String message)
    : super(code: 'SignatureDoesNotMatch', message: message);
}

/// Service is unable to handle request.
class S3ServiceUnavailableException extends S3Exception {
  const S3ServiceUnavailableException(String message)
    : super(code: 'ServiceUnavailable', message: message);
}

/// Reduce your request rate.
class S3SlowDownException extends S3Exception {
  const S3SlowDownException(String message)
    : super(code: 'SlowDown', message: message);
}

/// You are being redirected to the bucket while DNS updates.
class S3TemporaryRedirectException extends S3Exception {
  const S3TemporaryRedirectException(String message)
    : super(code: 'TemporaryRedirect', message: message);
}

/// The provided token must be refreshed.
class S3TokenRefreshRequiredException extends S3Exception {
  const S3TokenRefreshRequiredException(String message)
    : super(code: 'TokenRefreshRequired', message: message);
}

/// You have attempted to create more buckets than allowed.
class S3TooManyBucketsException extends S3Exception {
  const S3TooManyBucketsException(String message)
    : super(code: 'TooManyBuckets', message: message);
}

/// This request does not support content.
class S3UnexpectedContentException extends S3Exception {
  const S3UnexpectedContentException(String message)
    : super(code: 'UnexpectedContent', message: message);
}

/// The email address you provided does not match any account on record.
class S3UnresolvableGrantByEmailAddressException extends S3Exception {
  const S3UnresolvableGrantByEmailAddressException(String message)
    : super(code: 'UnresolvableGrantByEmailAddress', message: message);
}

/// The bucket POST must contain the specified field name. If it is
/// specified, check the order of the fields.
class S3UserKeyMustBeSpecifiedException extends S3Exception {
  const S3UserKeyMustBeSpecifiedException(String message)
    : super(code: 'UserKeyMustBeSpecified', message: message);
}
