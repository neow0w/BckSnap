import 'api_client.dart';

class GeoPoint {
  const GeoPoint({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

class ClinicDoctor {
  const ClinicDoctor({
    required this.id,
    required this.userId,
    required this.name,
    required this.specializations,
    required this.professionalInfo,
    required this.supportsOnline,
    required this.supportsPhysical,
    this.isDemo = false,
  });

  final int id;
  final int userId;
  final String? name;
  final List<String> specializations;
  final String? professionalInfo;
  final bool supportsOnline;
  final bool supportsPhysical;
  final bool isDemo;

  factory ClinicDoctor.fromJson(Map<String, dynamic> json) => ClinicDoctor(
    id: json['id'] as int,
    userId: json['user_id'] as int,
    name: json['name'] as String?,
    specializations: (json['specializations'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(),
    professionalInfo: json['professional_info'] as String?,
    supportsOnline: json['supports_online'] as bool? ?? false,
    supportsPhysical: json['supports_physical'] as bool? ?? false,
    isDemo: json['is_demo'] as bool? ?? false,
  );
}

class ClinicDemoAppointmentType {
  const ClinicDemoAppointmentType({
    required this.mode,
    required this.name,
    required this.simulationOnly,
  });

  final String mode;
  final String name;
  final bool simulationOnly;

  factory ClinicDemoAppointmentType.fromJson(Map<String, dynamic> json) =>
      ClinicDemoAppointmentType(
        mode: json['mode'] as String,
        name: json['name'] as String,
        simulationOnly: json['simulation_only'] as bool? ?? true,
      );
}

class ClinicInfo {
  const ClinicInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.phone,
    required this.email,
    required this.timezone,
    required this.operatingHours,
    required this.supportsOnline,
    required this.supportsPhysical,
    this.demoOperatingHours = const {},
    this.demoAppointmentTypes = const [],
    required this.services,
    required this.doctors,
    required this.distanceKm,
  });

  final int id;
  final String name;
  final String? description;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? email;
  final String timezone;
  final Map<String, dynamic> operatingHours;
  final bool supportsOnline;
  final bool supportsPhysical;
  final Map<String, dynamic> demoOperatingHours;
  final List<ClinicDemoAppointmentType> demoAppointmentTypes;
  final List<String> services;
  final List<ClinicDoctor> doctors;
  final double? distanceKm;

  bool get hasMapLocation =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  factory ClinicInfo.fromJson(Map<String, dynamic> json) => ClinicInfo(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String?,
    address: json['address'] as String,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    timezone: json['timezone'] as String? ?? 'UTC',
    operatingHours: Map<String, dynamic>.from(
      json['operating_hours'] as Map? ?? const {},
    ),
    supportsOnline: json['supports_online'] as bool? ?? false,
    supportsPhysical: json['supports_physical'] as bool? ?? false,
    demoOperatingHours: Map<String, dynamic>.from(
      json['demo_operating_hours'] as Map? ?? const {},
    ),
    demoAppointmentTypes: (json['demo_appointment_types'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => ClinicDemoAppointmentType.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList(),
    services: (json['services'] as List? ?? const [])
        .map((value) => value is Map ? value['name']?.toString() ?? '' : '')
        .where((value) => value.isNotEmpty)
        .toList(),
    doctors: (json['doctors'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => ClinicDoctor.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
    distanceKm: (json['distance_km'] as num?)?.toDouble(),
  );
}

class AppointmentSlot {
  const AppointmentSlot({
    required this.startsAt,
    required this.endsAt,
    required this.mode,
  });

  final DateTime startsAt;
  final DateTime endsAt;
  final String mode;

  factory AppointmentSlot.fromJson(Map<String, dynamic> json) =>
      AppointmentSlot(
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        mode: json['mode'] as String,
      );
}

class ClinicAppointment {
  const ClinicAppointment({
    required this.id,
    required this.userId,
    required this.status,
    required this.mode,
    required this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    required this.clinicId,
    required this.clinicName,
    required this.clinicAddress,
    required this.doctorId,
    required this.doctorName,
    required this.reference,
    required this.cancellationReason,
    this.isDemo = false,
  });

  final int id;
  final int userId;
  final String status;
  final String? mode;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? clinicId;
  final String? clinicName;
  final String? clinicAddress;
  final int? doctorId;
  final String? doctorName;
  final String? reference;
  final String? cancellationReason;
  final bool isDemo;

  bool get canCancel =>
      (status == 'pending' || status == 'approved') &&
      scheduledAt != null &&
      scheduledAt!.difference(DateTime.now().toUtc()) >=
          const Duration(hours: 24);
}

class ClinicNotification {
  const ClinicNotification({
    required this.id,
    required this.appointmentId,
    required this.eventType,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
  });

  final int id;
  final int appointmentId;
  final String eventType;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;

  factory ClinicNotification.fromJson(Map<String, dynamic> json) =>
      ClinicNotification(
        id: json['id'] as int,
        appointmentId: json['appointment_id'] as int,
        eventType: json['event_type'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        isRead: json['read_at'] != null,
      );
}

class ClinicService {
  ClinicService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<void> checkHealth() async {
    final result = await _api.get('/health');
    if (result is! Map ||
        result['status'] != 'ok' ||
        result['database'] != 'connected') {
      throw ApiException(
        503,
        'The server is reachable, but its database health check did not pass. Please retry or contact the server administrator.',
      );
    }
  }

  Future<List<ClinicInfo>> search({
    String? query,
    GeoPoint? location,
    double radiusKm = 50,
    String? service,
    String? mode,
  }) async {
    final parameters = <String, String>{};
    if (query != null && query.trim().isNotEmpty) {
      parameters['q'] = query.trim();
    }
    if (location != null) {
      parameters['latitude'] = location.latitude.toString();
      parameters['longitude'] = location.longitude.toString();
      parameters['radius_km'] = radiusKm.toString();
    }
    if (service != null && service.trim().isNotEmpty) {
      parameters['service'] = service.trim();
    }
    if (mode != null) parameters['mode'] = mode;
    final path = Uri(
      path: '/clinics',
      queryParameters: parameters.isEmpty ? null : parameters,
    );
    final result = await _api.get(path.toString());
    return (result as List)
        .whereType<Map>()
        .map((item) => ClinicInfo.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<GeoPoint>> geocode(String query) async {
    final path = Uri(
      path: '/clinics/geocode',
      queryParameters: {'q': query.trim()},
    );
    final result = await _api.get(path.toString());
    return (result as List)
        .whereType<Map>()
        .map(
          (item) => GeoPoint(
            label: item['label'] as String,
            latitude: (item['latitude'] as num).toDouble(),
            longitude: (item['longitude'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<ClinicInfo> clinic(int id) async {
    final result = await _api.get('/clinics/$id');
    return ClinicInfo.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<List<AppointmentSlot>> slots({
    required int clinicId,
    required int doctorId,
    required DateTime date,
    required String mode,
  }) async {
    final path = Uri(
      path: '/clinics/$clinicId/slots',
      queryParameters: {
        'doctor_id': '$doctorId',
        'on': _dateOnly(date),
        'mode': mode,
      },
    );
    final result = await _api.get(path.toString());
    return (result as List)
        .whereType<Map>()
        .map(
          (item) => AppointmentSlot.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<ClinicAppointment> book({
    required int clinicId,
    required int doctorId,
    required String mode,
    required DateTime startsAt,
  }) async {
    final result = await _api.post(
      '/appointments',
      body: {
        'clinic_id': clinicId,
        'doctor_id': doctorId,
        'mode': mode,
        'scheduled_at': startsAt.toUtc().toIso8601String(),
      },
    );
    return _appointmentFromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<List<ClinicAppointment>> appointments({String? state}) async {
    final path = Uri(
      path: '/appointments/mine',
      queryParameters: state == null ? null : {'state': state},
    );
    final result = await _api.get(path.toString());
    return (result as List)
        .whereType<Map>()
        .map((item) => _appointmentFromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<ClinicAppointment> appointment(int id) async {
    final result = await _api.get('/appointments/$id');
    return _appointmentFromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<ClinicAppointment> cancel(int id, String reason) async {
    final result = await _api.post(
      '/appointments/$id/cancel',
      body: {'reason': reason.trim()},
    );
    return _appointmentFromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<String> consultation(int id) async {
    final result = await _api.get('/appointments/$id/consultation');
    return (result as Map<String, dynamic>)['consultation_url'] as String;
  }

  Future<List<ClinicNotification>> notifications({
    bool unreadOnly = false,
  }) async {
    final result = await _api.get(
      '/appointments/notifications/mine${unreadOnly ? '?unread_only=true' : ''}',
    );
    return (result as List)
        .whereType<Map>()
        .map(
          (item) =>
              ClinicNotification.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> markNotificationRead(int id) async {
    await _api.patch('/appointments/notifications/$id/read');
  }

  Future<List<ClinicAppointment>> staffAppointments({String? state}) async {
    final path = Uri(
      path: '/appointments',
      queryParameters: state == null ? null : {'state': state},
    );
    final result = await _api.get(path.toString());
    return (result as List)
        .whereType<Map>()
        .map((item) => _appointmentFromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> reviewAppointment(int id, {required bool approve}) async {
    if (approve) {
      await _api.patch('/appointments/$id/approve');
    } else {
      await _api.patch('/appointments/$id/decline');
    }
  }

  Future<List<Map<String, dynamic>>> pendingDoctorApplications() async {
    final result = await _api.get('/clinic/staff/pending');

    return (result as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> approveDoctorApplication(int staffId) async {
    final result = await _api.post('/clinic/staff/$staffId/approve');

    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> rejectDoctorApplication(int staffId) async {
    final result = await _api.post('/clinic/staff/$staffId/reject');

    return Map<String, dynamic>.from(result as Map);
  }


  ClinicAppointment _appointmentFromJson(Map<String, dynamic> json) {
    final clinicId = json['clinic_id'] as int?;
    return ClinicAppointment(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      status: json['status'] as String,
      mode: json['mode'] as String?,
      scheduledAt: (json['scheduled_at'] as String?) == null
          ? null
          : DateTime.parse(json['scheduled_at'] as String).toUtc(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.parse(json['updated_at'] as String),
      clinicId: clinicId,
      clinicName: json['clinic_name'] as String?,
      clinicAddress: json['clinic_address'] as String?,
      doctorId: json['doctor_id'] as int?,
      doctorName: json['doctor_name'] as String?,
      reference: json['reference'] as String?,
      cancellationReason: json['cancellation_reason'] as String?,
      isDemo: json['is_demo'] as bool? ?? false,
    );
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String appointmentStatusLabel(String status) => switch (status) {
  'pending' => 'Pending',
  'approved' => 'Approved',
  'rejected' || 'declined' => 'Rejected',
  'cancelled' => 'Cancelled',
  'completed' => 'Completed',
  _ => status,
};
