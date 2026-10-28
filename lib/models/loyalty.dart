import '../utils/safe_parse.dart';
import '../widgets/common/status_badge.dart';

/// Reward loyalitas: hadiah yang bisa ditukar dengan poin.
/// Backend nyata: GET /loyalty/rewards (envelope, hanya active=true)
/// {id, name, points_required, discount_type, discount_value, active}.
/// Read-only di mobile; kelola reward dari web admin.
class LoyaltyReward {
  final int id;
  final String name;
  final int pointsRequired;
  final String? discountType;
  final double discountValue;
  final bool active;

  LoyaltyReward({
    required this.id,
    required this.name,
    this.pointsRequired = 0,
    this.discountType,
    this.discountValue = 0,
    this.active = true,
  });

  /// Alias kompatibel untuk kode lama (points_cost → points_required).
  int get pointsCost => pointsRequired;

  factory LoyaltyReward.fromJson(Map<String, dynamic> json) {
    return LoyaltyReward(
      id: safeInt(json['id']),
      name: safeString(json['name'], 'Tanpa nama'),
      pointsRequired: safeInt(
        json['points_required'] ?? json['points_cost'] ?? json['pointsCost'],
      ),
      discountType: (json['discount_type'] ?? json['discountType'])?.toString(),
      discountValue: safeDouble(
        json['discount_value'] ?? json['discountValue'],
      ),
      active: _safeBool(json['active'], true),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'points_required': pointsRequired,
    if (discountType != null) 'discount_type': discountType,
    'discount_value': discountValue,
    'active': active,
  };
}

/// Saldo poin pelanggan.
/// Backend nyata: GET /loyalty/summary?customer_id=
/// → {customer_id, name, total_points, points_earned, points_redeemed,
///    total_spent}.
class LoyaltyPoints {
  final int customerId;
  final String customerName;
  final int earned;
  final int redeemed;
  final int balance;
  final double totalSpent;

  LoyaltyPoints({
    this.customerId = 0,
    this.customerName = '',
    this.earned = 0,
    this.redeemed = 0,
    this.balance = 0,
    this.totalSpent = 0,
  });

  factory LoyaltyPoints.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'];
    final earned = safeInt(
      json['points_earned'] ?? json['earned'] ?? json['total_earned'],
    );
    final redeemed = safeInt(
      json['points_redeemed'] ?? json['redeemed'] ?? json['total_redeemed'],
    );
    final balance = json['total_points'] != null
        ? safeInt(json['total_points'])
        : (json['balance'] != null
              ? safeInt(json['balance'])
              : earned - redeemed);
    final directName = safeString(json['name'], '');
    return LoyaltyPoints(
      customerId: safeInt(json['customer_id'] ?? json['customerId']),
      customerName: directName.isEmpty
          ? (json['customer_name']?.toString() ??
                (customer is Map ? safeString(customer['name'], '') : ''))
          : directName,
      earned: earned,
      redeemed: redeemed,
      balance: balance < 0 ? 0 : balance,
      totalSpent: safeDouble(json['total_spent'] ?? json['totalSpent']),
    );
  }
}

/// Grup pelanggan: Regular/Member/Reseller + diskon.
/// Kontrak: GET /customer-groups.
class CustomerGroup {
  final int id;
  final String name;
  final double discountPercent;
  final double minSpent;
  final int memberCount;

  CustomerGroup({
    required this.id,
    required this.name,
    this.discountPercent = 0,
    this.minSpent = 0,
    this.memberCount = 0,
  });

  factory CustomerGroup.fromJson(Map<String, dynamic> json) {
    return CustomerGroup(
      id: safeInt(json['id']),
      name: safeString(
        json['name'],
        json['code']?.toString() ?? 'Tanpa nama',
      ),
      discountPercent: safeDouble(
        json['discount_percent'] ??
            json['discount'] ??
            json['discountPercent'],
      ),
      minSpent: safeDouble(
        json['min_spent'] ?? json['minSpent'] ?? json['min_purchase'],
      ),
      memberCount: safeInt(
        json['member_count'] ?? json['memberCount'] ?? json['customers_count'],
      ),
    );
  }
}

/// Template diskon untuk checkout POS.
/// Backend nyata: GET /discounts (READ-ONLY, envelope; tanpa filter
/// type/active di server) {id, name, type, value, min_purchase,
/// buy_quantity, get_quantity, start_date, end_date, active, outlet_id}.
/// Kelola template dari web admin. type: percent|fixed|buy_x_get_y
class DiscountTemplate {
  final int id;
  final String name;
  final String type;
  final double value;
  final double minPurchase;
  final int buyQty;
  final int getQty;
  final bool active;
  final String? startAt;
  final String? endAt;

  DiscountTemplate({
    required this.id,
    required this.name,
    this.type = 'percent',
    this.value = 0,
    this.minPurchase = 0,
    this.buyQty = 0,
    this.getQty = 0,
    this.active = true,
    this.startAt,
    this.endAt,
  });

  factory DiscountTemplate.fromJson(Map<String, dynamic> json) {
    return DiscountTemplate(
      id: safeInt(json['id']),
      name: safeString(json['name'], 'Tanpa nama'),
      type: safeString(json['type'], 'percent'),
      value: safeDouble(json['value']),
      minPurchase: safeDouble(json['min_purchase'] ?? json['minPurchase']),
      buyQty: safeInt(
        json['buy_quantity'] ?? json['buy_qty'] ?? json['buyQty'],
      ),
      getQty: safeInt(
        json['get_quantity'] ?? json['get_qty'] ?? json['getQty'],
      ),
      active: _safeBool(json['active'], true),
      startAt:
          (json['start_date'] ?? json['start_at'])?.toString(),
      endAt: (json['end_date'] ?? json['end_at'])?.toString(),
    );
  }
}

bool _safeBool(dynamic v, bool fallback) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

/// Label Bahasa Indonesia untuk tipe diskon.
String discountTypeLabel(String type) {
  switch (type) {
    case 'percent':
      return 'Persen (%)';
    case 'fixed':
      return 'Nominal (Rp)';
    case 'buy_x_get_y':
      return 'Beli X Gratis Y';
    default:
      return type.isEmpty ? 'Diskon' : type;
  }
}

BadgeTone toneForDiscountActive(bool active) =>
    active ? BadgeTone.success : BadgeTone.neutral;

BadgeTone toneForRewardActive(bool active) =>
    active ? BadgeTone.success : BadgeTone.neutral;
