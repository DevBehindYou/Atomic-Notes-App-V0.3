// Browser HTTP failures are ClientException, handled by sync_policy.dart.
// Never infer connectivity from exception text or classify Server refusals.
bool isPlatformNetworkFailure(Object error) => false;
