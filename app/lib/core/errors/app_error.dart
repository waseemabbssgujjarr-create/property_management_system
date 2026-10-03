/// Domain error types for Munshi.
/// Never expose raw Supabase/network exceptions to the UI.
/// Map all external errors to AppError before surfacing.
sealed class AppError {
  final String message;
  const AppError(this.message);
}

/// Network not reachable
class NetworkError extends AppError {
  const NetworkError() : super('انٹرنیٹ نہیں ہے');
}

/// Unauthorized (not logged in or session expired)
class UnauthorizedError extends AppError {
  const UnauthorizedError() : super('لاگ ان ضروری ہے');
}

/// Forbidden (logged in but insufficient role)
class ForbiddenError extends AppError {
  const ForbiddenError() : super('اجازت نہیں');
}

/// Resource not found
class NotFoundError extends AppError {
  const NotFoundError([String message = 'نہیں ملا'])
      : super(message);
}

/// Validation failure with field-level details
class ValidationError extends AppError {
  final Map<String, String> fields;
  const ValidationError(String message, this.fields) : super(message);
}

/// OTP-specific errors
class OtpError extends AppError {
  final OtpErrorKind kind;
  const OtpError(this.kind, String message) : super(message);
}

enum OtpErrorKind {
  invalid,
  expired,
  tooManyAttempts,
  sendFailed,
}

/// Server returned an unexpected error
class ServerError extends AppError {
  final int? statusCode;
  const ServerError([String message = 'سرور میں خرابی', this.statusCode])
      : super(message);
}

/// Financial integrity error (used for invariant violations)
class FinancialIntegrityError extends AppError {
  const FinancialIntegrityError(String message) : super(message);
}

/// Sync/offline error
class SyncError extends AppError {
  const SyncError([String message = 'سیو نہیں ہوا']) : super(message);
}

/// Maps Supabase/network exceptions to domain errors.
AppError mapException(Object e) {
  if (e is AppError) return e;

  final msg = e.toString().toLowerCase();

  if (msg.contains('network') ||
      msg.contains('socket') ||
      msg.contains('connection') ||
      msg.contains('reach')) {
    return const NetworkError();
  }

  if (msg.contains('jwt') ||
      msg.contains('auth') ||
      msg.contains('token') ||
      msg.contains('session')) {
    return const UnauthorizedError();
  }

  if (msg.contains('row-level') ||
      msg.contains('rls') ||
      msg.contains('permission') ||
      msg.contains('policy')) {
    return const ForbiddenError();
  }

  if (msg.contains('not found') || msg.contains('0 rows')) {
    return const NotFoundError();
  }

  if (msg.contains('otp') || msg.contains('verification')) {
    return const OtpError(OtpErrorKind.invalid, 'کوڈ درست نہیں');
  }

  return ServerError(e.toString());
}
