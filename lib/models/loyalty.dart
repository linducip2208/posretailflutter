import '../utils/safe_parse.dart';
import '../widgets/common/status_badge.dart';

/// Reward loyalitas: hadiah yang bisa ditukar dengan poin.
/// Kontrak: GET/POST /loyalty-rewards {name, points_cost, stock, active}
class LoyaltyReward {
  final int id;
  final String name;
  final int pointsCost;
  final int stock;
  final bool active;

  LoyaltyReward({
    required this.id,
    required this.name,
    this.pointsCost = 0,
    this.stock = 0,
    this.active = true,
  });

  factory LoyaltyReward.fromJson(Map<String, dynamic> json) {
    return LoyaltyReward(
      id: safeInt(json['id']),
      name: safeString(json['name'], 'Tanpa nama'),
      pointsCost: safeInt(json['points_cost'] ?? json['pointsCost']),
      stock: safeInt(json['stock']),
      active: _safeBool(json['active'], true),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'points_cost': pointsCost,
    'stock': stock,
    'active': active,
  };
}

/// Saldo poin pelanggan.
/// Kontrak: GET /loyalty-points?customer_id= → earned/redeemed + saldo.
class LoyaltyPoints {
  final int customerId;
  final String customerName;
  final int earned;
  final int redeemed;
  final int balance;

  LoyaltyPoints({
    this.customerId = 0,
    this.customerName = '',
    this.earned = 0,
    this.redeemed = 0,
    this.balance = 0,
  });

  factory LoyaltyPoints.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'];
    final earned = safeInt(json['earned'] ?? json['total_earned']);
    final redeemed = safeInt(json['redeemed'] ?? json['total_redeemed']);
    final balance = json['balance'] != null
        ? safeInt(json['balance'])
        : earned - redeemed;
    return LoyaltyPoints(
      customerId: safeInt(json['customer_id'] ?? json['customerId']),
      customerName:
          json['customer_name']?.toString() ??
          (customer is Map ? safeString(customer['name'], '') : ''),
      earned: earned,
      redeemed: redeemed,
      balance: balance < 0 ? 0 : balance,
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
/// Kontrak: GET/POST /discounts {name, type, value, min_purchase?,
/// buy_qty?, get_qty?, start_at?, end_at?, active}
/// type: percent|fixed|buy_x_get_y
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
      buyQty: safeInt(json['buy_qty'] ?? json['buyQty']),
      getQty: safeInt(json['get_qty'] ?? json['getQty']),
      active: _safeBool(json['active'], true),
      startAt: json['start_at']?.toString(),
      endAt: json['end_at']?.toString(),
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
