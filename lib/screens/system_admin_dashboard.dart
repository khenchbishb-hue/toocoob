import 'package:flutter/material.dart';

class SystemAdminDashboard extends StatelessWidget {
  const SystemAdminDashboard({super.key, required this.onLogout, required this.onBack});

  final VoidCallback onLogout;
  final VoidCallback onBack;

  void _preview(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature хэсгийг дараагийн алхамд холбоно.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Хэрэглэгчийн нүүр рүү буцах',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('TOOCOOB  •  SYSTEM ADMIN'),
        backgroundColor: const Color(0xFF172554),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Гарах',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Системийн хяналтын самбар',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Хэрэглэгч, бүлэг, аюулгүй байдал болон системийн ерөнхий удирдлага.'),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 960 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.45,
              children: const [
                _MetricCard('Нийт хэрэглэгч', '—', Icons.people_alt_outlined, Color(0xFF2563EB)),
                _MetricCard('Идэвхтэй бүлэг', '—', Icons.groups_outlined, Color(0xFF16A34A)),
                _MetricCard('Хүлээгдэж буй хүсэлт', '—', Icons.mark_email_unread_outlined, Color(0xFFF59E0B)),
                _MetricCard('Идэвхтэй ширээ', '—', Icons.table_restaurant_outlined, Color(0xFF8B5CF6)),
              ],
            );
          }),
          const SizedBox(height: 28),
          const Text('Удирдлага', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 16, children: [
            _ActionCard(icon: Icons.person_add_alt_1, title: 'Хэрэглэгчийн бүртгэл', subtitle: 'Урьдчилсан profile, activation code, account төлөв', onTap: () => _preview(context, 'Хэрэглэгчийн бүртгэл')),
            _ActionCard(icon: Icons.groups, title: 'Бүлгүүд', subtitle: 'Бүх бүлгийн ерөнхий хяналт ба асуудал шийдэх', onTap: () => _preview(context, 'Бүлгүүд')),
            _ActionCard(icon: Icons.security, title: 'Аюулгүй байдал', subtitle: 'Account recovery, эрх, идэвхгүй account', onTap: () => _preview(context, 'Аюулгүй байдал')),
            _ActionCard(icon: Icons.settings_outlined, title: 'Системийн тохиргоо', subtitle: 'Суурь тохиргоо, deploy болон техникийн мэдээлэл', onTap: () => _preview(context, 'Системийн тохиргоо')),
          ]),
          const SizedBox(height: 28),
          const _InfoPanel(),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon, this.color);
  final String label; final String value; final IconData icon; final Color color;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const Spacer(), Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(color: Colors.black54))])));
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 285,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 30, color: const Color(0xFF1D4ED8)),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel();
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)), child: const Row(children: [Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF1D4ED8)), SizedBox(width: 12), Expanded(child: Text('System Admin нь тоглолтын ширээг шууд удирдахгүй. Тоглоомын үеийн эрх нь зөвхөн тухайн бүлгийн owner болон registrar-д хамаарна.'))]));
}
