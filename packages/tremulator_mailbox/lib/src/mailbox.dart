import 'dart:convert';
import 'dart:typed_data';

import 'package:fhir_r4/fhir_r4.dart';
import 'package:fhir_r4_at_rest/fhir_r4_at_rest.dart';
import 'package:http/http.dart' as http;
import 'package:tremulator_mailbox/src/envelope.dart';
import 'package:tremulator_mailbox/src/labels.dart';
import 'package:tremulator_mailbox/src/session.dart';
import 'package:tremulator_mailbox/src/wakeup.dart';

/// The hex form of a conversation id, as it appears in identifiers.
String conversationKey(Uint8List id) =>
    id.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// One phone's view of the group's server.
///
/// Every call is one FHIR request. Nothing here reads a payload.
class Mailbox {
  /// A mailbox on [base] (the server root, e.g. `http://10.42.0.1:8080`),
  /// signed in with [token] (null on a server with authentication off).
  Mailbox({required this.base, this.token, http.Client? client})
    : _client = client ?? http.Client();

  /// The server root.
  final Uri base;

  /// The bearer token, or null.
  final String? token;
  final http.Client _client;
  String? _device;

  /// This phone's Device id on the server, once [register] has run.
  String get device {
    final d = _device;
    if (d == null) {
      throw const MailboxError('register() first');
    }
    return d;
  }

  Map<String, String> get _headers => {
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Registers this phone as a Device named [deviceName] carrying its
  /// public signing key, or finds the one already there. Returns the id.
  Future<String> register({
    required String deviceName,
    required Uint8List publicKey,
  }) async {
    final device = Device(
      identifier: [
        Identifier(
          system: FhirUri(deviceNameSystem),
          value: FhirString(deviceName),
        ),
        Identifier(
          system: FhirUri(signingKeySystem),
          value: FhirString(base64Url.encode(publicKey)),
        ),
      ],
      status: FHIRDeviceStatus.active,
    );
    final r = await FhirCreateRequest(
      base: base,
      resourceType: 'Device',
      resource: device.toJson(),
      headers: {
        ..._headers,
        'If-None-Exist': 'identifier=$deviceNameSystem|$deviceName',
      },
      client: _client,
    ).sendRequest();
    _check(r, [200, 201]);
    return _device = _idOf(r);
  }

  /// The Device id for [deviceName], or null if it is not registered.
  Future<String?> findDevice(String deviceName) async {
    final bundle = await _search('Device', {
      'identifier': '$deviceNameSystem|$deviceName',
      '_count': '1',
    });
    final entries = bundle.entry ?? const [];
    return entries.isEmpty ? null : entries.first.resource?.id?.valueString;
  }

  /// The public signing key of Device [deviceId], from its identifier.
  Future<Uint8List?> signingKeyOf(String deviceId) async {
    final r = await _client.get(_uri('Device/$deviceId'), headers: _headers);
    _check(r, [200]);
    final d = Device.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    for (final i in d.identifier ?? const <Identifier>[]) {
      if (i.system?.valueString == signingKeySystem &&
          i.value?.valueString != null) {
        return base64Url.decode(i.value!.valueString!);
      }
    }
    return null;
  }

  /// Publishes [keyPackages] for other phones to take, one resource each.
  Future<void> publishKeyPackages(List<Uint8List> keyPackages) async {
    for (final kp in keyPackages) {
      await _create(
        _communication(label: Label.keyPackage, payloads: [(mlsMediaType, kp)]),
      );
    }
  }

  /// Takes one of [deviceId]'s key packages, removing it from the server so
  /// nobody else can. Null when the stock is empty. Two takers racing for the
  /// same one are settled by the delete: the loser's delete finds nothing and
  /// moves to the next.
  Future<Uint8List?> takeKeyPackage(String deviceId) async {
    final bundle = await _search('Communication', {
      'sender': 'Device/$deviceId',
      'category': '$labelSystem|${Label.keyPackage.code}',
      '_sort': '_lastUpdated',
      '_count': '5',
    });
    for (final e in bundle.entry ?? const <BundleEntry>[]) {
      final c = e.resource;
      if (c is! Communication) {
        continue;
      }
      final id = c.id?.valueString;
      if (id == null) {
        continue;
      }
      final r = await FhirDeleteRequest(
        base: base,
        resourceType: 'Communication',
        id: id,
        headers: _headers,
        client: _client,
      ).sendRequest();
      if (r.statusCode == 200 || r.statusCode == 204) {
        return _firstPayload(c);
      }
    }
    return null;
  }

  /// Sends [bytes] labelled [label] to Device [to]. Returns the server id.
  Future<String> send({
    required String to,
    required Label label,
    required Uint8List bytes,
  }) => _create(
    _communication(
      label: label,
      recipients: [to],
      payloads: [(mlsMediaType, bytes)],
    ),
  );

  /// Offers a commit that would move [conversation] to [epoch], with the
  /// snapshot (GroupInfo and key tree) beside it, addressed to every member
  /// in [to]. Returns true if the server took it, false if another phone's
  /// commit for that epoch was there first (the server keeps the first:
  /// conditional create on the commit identifier, R4 http.html "cond-create",
  /// fhirant `resource_handler.dart` read 2026-10-06).
  Future<bool> sendCommit({
    required List<String> to,
    required Uint8List conversation,
    required BigInt epoch,
    required Uint8List commit,
    required Uint8List groupInfo,
    required Uint8List ratchetTree,
  }) async {
    final key = '${conversationKey(conversation)}:$epoch';
    final c = _communication(
      label: Label.commit,
      recipients: to,
      payloads: [
        (mlsMediaType, commit),
        (mlsMediaType, groupInfo),
        (octetStream, ratchetTree),
      ],
      identifier: Identifier(
        system: FhirUri(commitSystem),
        value: FhirString(key),
      ),
    );
    final r = await FhirCreateRequest(
      base: base,
      resourceType: 'Communication',
      resource: c.toJson(),
      headers: {..._headers, 'If-None-Exist': 'identifier=$commitSystem|$key'},
      client: _client,
    ).sendRequest();
    _check(r, [200, 201]);
    return r.statusCode == 201;
  }

  /// The commit that moves [conversation] from [epoch] to the next, or null
  /// if the conversation has not moved past [epoch]. A phone walks forward
  /// from its own epoch; the last envelope's `extra` is the snapshot to
  /// rejoin from if it is out of step.
  Future<Envelope?> commitAfter(Uint8List conversation, BigInt epoch) async {
    final key = '${conversationKey(conversation)}:${epoch + BigInt.one}';
    final bundle = await _search('Communication', {
      'identifier': '$commitSystem|$key',
      '_count': '1',
    });
    final entries = bundle.entry ?? const <BundleEntry>[];
    if (entries.isEmpty) {
      return null;
    }
    final c = entries.first.resource;
    return c is Communication ? _envelope(c) : null;
  }

  /// Everything addressed to this phone that is not a commit, oldest first.
  /// Call [acknowledge] on each once it is safely stored.
  Future<List<Envelope>> collect({int count = 100}) async {
    final bundle = await _search('Communication', {
      'recipient': 'Device/$device',
      'status': 'in-progress',
      'category': [
        for (final l in Label.values)
          if (l != Label.commit) '$labelSystem|${l.code}',
      ].join(','),
      '_sort': '_lastUpdated',
      '_count': '$count',
    });
    return [
      for (final e in bundle.entry ?? const <BundleEntry>[])
        if (e.resource case final Communication c) _envelope(c),
    ];
  }

  /// Deletes a collected blob so the server keeps nothing (D8).
  Future<void> acknowledge(String id) async {
    final r = await FhirDeleteRequest(
      base: base,
      resourceType: 'Communication',
      id: id,
      headers: _headers,
      client: _client,
    ).sendRequest();
    _check(r, [200, 204, 404, 410]);
  }

  /// How many blobs the server still holds for this phone, any label.
  Future<int> pending() async {
    final bundle = await _search('Communication', {
      'recipient': 'Device/$device',
      '_summary': 'count',
    });
    return bundle.total?.valueInt ?? 0;
  }

  /// Opens the wake-up connection: a Subscription on everything addressed to
  /// this phone, bound over the server's websocket.
  Future<Wakeup> wakeups() async {
    final sub = Subscription(
      status: SubscriptionStatusCodes.requested,
      reason: FhirString('tremulator wake-up for Device/$device'),
      criteria: FhirString(
        'Communication?recipient=Device/$device&status=in-progress',
      ),
      channel: const SubscriptionChannel(
        type: SubscriptionChannelType.websocket,
      ),
    );
    final id = await _create(sub);
    final socket = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/ws',
    );
    return Wakeup.bind(socket: socket, subscriptionId: id);
  }

  /// Releases the HTTP client.
  void close() => _client.close();

  // ---- private ------------------------------------------------------------

  Communication _communication({
    required Label label,
    required List<(String, Uint8List)> payloads,
    List<String> recipients = const [],
    Identifier? identifier,
  }) => Communication(
    status: EventStatus.inProgress,
    category: [
      CodeableConcept(
        coding: [
          Coding(system: FhirUri(labelSystem), code: FhirCode(label.code)),
        ],
      ),
    ],
    identifier: identifier == null ? null : [identifier],
    sender: Reference(reference: FhirString('Device/$device')),
    recipient: recipients.isEmpty
        ? null
        : [
            for (final r in recipients)
              Reference(reference: FhirString('Device/$r')),
          ],
    sent: FhirDateTime.fromDateTime(DateTime.now().toUtc()),
    payload: [
      for (final (type, bytes) in payloads)
        CommunicationPayload(
          contentX: Attachment(
            contentType: FhirCode(type),
            data: FhirBase64Binary(base64.encode(bytes)),
          ),
        ),
    ],
  );

  Envelope _envelope(Communication c) {
    final payloads = [
      for (final p in c.payload ?? const <CommunicationPayload>[])
        if (p.contentX case final Attachment a) a.data?.object ?? Uint8List(0),
    ];
    final code =
        c.category?.firstOrNull?.coding?.firstOrNull?.code?.valueString;
    return Envelope(
      id: c.id?.valueString ?? '',
      label: Label.fromCode(code) ?? Label.message,
      bytes: payloads.isEmpty ? Uint8List(0) : payloads.first,
      extra: payloads.length > 1 ? payloads.sublist(1) : const <Uint8List>[],
      from: c.sender?.reference?.valueString?.replaceFirst('Device/', ''),
      sent: c.sent?.valueString,
    );
  }

  Uint8List _firstPayload(Communication c) {
    final p = c.payload?.firstOrNull?.contentX;
    return p is Attachment ? (p.data?.object ?? Uint8List(0)) : Uint8List(0);
  }

  Future<String> _create(Resource resource) async {
    final r = await FhirCreateRequest(
      base: base,
      resourceType: resource.resourceType.toString(),
      resource: resource.toJson(),
      headers: _headers,
      client: _client,
    ).sendRequest();
    _check(r, [201]);
    return _idOf(r);
  }

  Future<Bundle> _search(String type, Map<String, String> params) async {
    final r = await _client.get(_uri(type, params), headers: _headers);
    _check(r, [200]);
    return Bundle.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Uri _uri(String path, [Map<String, String>? params]) => base.replace(
    path: '${base.path}/$path',
    queryParameters: {...?params, '_format': 'json'},
  );

  String _idOf(http.Response r) {
    final body = jsonDecode(r.body);
    final id = body is Map<String, dynamic> ? body['id'] : null;
    if (id is! String) {
      throw MailboxError('server answered ${r.statusCode} without an id');
    }
    return id;
  }

  void _check(http.Response r, List<int> ok) {
    if (!ok.contains(r.statusCode)) {
      throw MailboxError(
        '${r.request?.method} ${r.request?.url}: ${r.statusCode} ${r.body}',
      );
    }
  }
}
