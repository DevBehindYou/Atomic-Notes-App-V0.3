import 'dart:io';

bool isPlatformNetworkFailure(Object error) =>
    error is SocketException || error is TlsException || error is HttpException;
