/// ***************************************************************
///  APP: ZIRO
///  AUTHOR: Jeroguez
///  VERSION: 2.4 COMPLETA (Ahorro Real + Estadísticas Limpias + Euro)
/// ***************************************************************

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('es', null);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MaterialApp(
    home: ZiroApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class Entry {
  String id, title, type, category, currency;
  double amount;
  Entry({required this.id, required this.title, required this.amount, required this.type, this.category = "Otros", this.currency = "Bs"});

  Map<String, dynamic> toMap() => {'id': id, 'title': title, 'amount': amount, 'type': type, 'category': category, 'currency': currency};
  factory Entry.fromMap(Map<String, dynamic> m) => Entry(id: m['id'], title: m['title'], amount: m['amount'], type: m['type'], category: m['category'] ?? "Otros", currency: m['currency'] ?? "Bs");
}

class Goal {
  final String name, imagePath, currency;
  final double targetAmount;
  double savedAmount;
  Goal({required this.name, required this.targetAmount, required this.imagePath, required this.currency, this.savedAmount = 0.0});

  Map<String, dynamic> toMap() => {'name': name, 'targetAmount': targetAmount, 'imagePath': imagePath, 'currency': currency, 'savedAmount': savedAmount};
  factory Goal.fromMap(Map<String, dynamic> m) => Goal(
      name: m['name'], targetAmount: m['targetAmount'], imagePath: m['imagePath'],
      currency: m['currency'] ?? "\$", savedAmount: (m['savedAmount'] ?? 0.0).toDouble()
  );
}

class ZiroApp extends StatefulWidget {
  const ZiroApp({super.key});
  @override
  ZiroAppState createState() => ZiroAppState();
}

class ZiroAppState extends State<ZiroApp> with TickerProviderStateMixin {
  final LocalAuthentication auth = LocalAuthentication();
  final NumberFormat _f = NumberFormat.decimalPattern('es_ES');

  List<Entry> _entries = [];
  Goal? _currentGoal;
  String _userName = "", _mainCurrency = "Bs";
  double _initialMain = 0.0, _initialSec = 0.0, _emergencyFund = 0.0;

  double _dollarPriceBCV = 1.0;
  double _euroPrice = 1.0;

  bool _isFirstTime = true, _isAuthorized = false;
  int _selectedTabIndex = 0;

  bool _showTutorial = false;
  bool _tutorialCompleted = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  final Map<String, IconData> _catIcons = {
    "Comida": Icons.restaurant,
    "Transporte": Icons.directions_car,
    "Servicios": Icons.lightbulb,
    "Ocio": Icons.videogame_asset,
    "Salud": Icons.medical_services,
    "Educación": Icons.school,
    "Otros": Icons.more_horiz,
    "Emergencia": Icons.warning_amber_rounded
  };

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _load();
    _updateRates();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
    _fadeController.forward();
    _slideController.forward();
  }

  double _parseAmount(String text) {
    if (text.isEmpty) return 0.0;
    String normalized = text.replaceAll(',', '.');
    if ('.'.allMatches(normalized).length > 1) {
      List<String> parts = normalized.split('.');
      String decimal = parts.removeLast();
      normalized = parts.join('') + '.' + decimal;
    }
    return double.tryParse(normalized) ?? 0.0;
  }

  // ==================== ACTUALIZACIÓN DE TASAS (VERSIÓN CORREGIDA) ====================
  Future<void> _updateRates() async {
    if (_mainCurrency != "Bs") return;

    try {
      final response = await http.get(Uri.parse('https://ve.dolarapi.com/v1/monedas'));

      if (mounted && response.statusCode == 200) {
        final List<dynamic> monedas = jsonDecode(response.body);

        setState(() {
          // Buscar el Dólar (BCV)
          final dolar = monedas.firstWhere(
                (m) => m['nombre'] == 'Dólar' || m['codigo'] == 'USD',
            orElse: () => null,
          );
          if (dolar != null) {
            _dollarPriceBCV = (dolar['promedio'] ?? dolar['precio'] ?? 1.0).toDouble();
            print("✅ Dólar actualizado: $_dollarPriceBCV Bs");
          }

          // Buscar el Euro
          final euro = monedas.firstWhere(
                (m) => m['nombre'] == 'Euro' || m['codigo'] == 'EUR',
            orElse: () => null,
          );
          if (euro != null) {
            _euroPrice = (euro['promedio'] ?? euro['precio'] ?? 1.0).toDouble();
            print("✅ Euro actualizado: $_euroPrice Bs");
          } else {
            // Si no encuentra el Euro, calcular basado en Dólar (tasa EUR/USD ≈ 1.08)
            _euroPrice = _dollarPriceBCV / 1.08;
            print("⚠️ Euro no encontrado, usando cálculo: $_euroPrice Bs");
          }
        });
      } else {
        print("❌ Error en API /v1/monedas: ${response.statusCode}");
        if (mounted) {
          setState(() {
            _euroPrice = _dollarPriceBCV / 1.08;
          });
        }
      }
      _save();
    } catch (e) {
      print("❌ Excepción al obtener tasas: $e");
      if (mounted) {
        setState(() {
          _euroPrice = _dollarPriceBCV / 1.08;
        });
      }
    }
  }

  Future<void> _authenticate() async {
    try {
      bool canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canCheck) {
        if (mounted) setState(() => _isAuthorized = true);
        return;
      }
      bool authResult = await auth.authenticate(
        localizedReason: 'Acceso seguro a Ziro',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (mounted) {
        setState(() {
          _isAuthorized = authResult;
          if (authResult) {
            _fadeController.forward();
            _slideController.forward();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isAuthorized = true);
    }
  }

  _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = p.getString('u_name') ?? "";
        _mainCurrency = p.getString('u_curr') ?? "Bs";
        _initialMain = p.getDouble('u_main_val') ?? 0.0;
        _initialSec = p.getDouble('u_sec_val') ?? 0.0;
        _emergencyFund = p.getDouble('u_emergency') ?? 0.0;
        _dollarPriceBCV = p.getDouble('u_dollar_bcv') ?? 1.0;
        _euroPrice = p.getDouble('u_euro') ?? 1.0;
        _isFirstTime = _userName.isEmpty;

        _tutorialCompleted = p.getBool('tutorial_completed') ?? false;
        _showTutorial = !_tutorialCompleted && !_isFirstTime;

        final String? data = p.getString('z_db_v14');
        if (data != null) _entries = (jsonDecode(data) as List).map((e) => Entry.fromMap(e)).toList();
        final String? goalData = p.getString('z_goal_v14');
        if (goalData != null) _currentGoal = Goal.fromMap(jsonDecode(goalData));
      });
    }
    if (!_isFirstTime) _authenticate();
  }

  _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('u_name', _userName);
    await p.setString('u_curr', _mainCurrency);
    await p.setDouble('u_main_val', _initialMain);
    await p.setDouble('u_sec_val', _initialSec);
    await p.setDouble('u_emergency', _emergencyFund);
    await p.setDouble('u_dollar_bcv', _dollarPriceBCV);
    await p.setDouble('u_euro', _euroPrice);
    await p.setString('z_db_v14', jsonEncode(_entries.map((e) => e.toMap()).toList()));
    if (_currentGoal != null) await p.setString('z_goal_v14', jsonEncode(_currentGoal!.toMap()));
    await p.setBool('tutorial_completed', _tutorialCompleted);
  }

  // ==================== PANTALLA DE CONFIGURACIÓN INICIAL ====================

  Widget _buildSetup() {
    final n = TextEditingController();
    final b = TextEditingController();
    final u = TextEditingController();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.grey.shade50],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Configuración inicial",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  "Bienvenido a Ziro",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Configura tus saldos actuales",
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: n,
                        decoration: InputDecoration(
                          labelText: "Tu Nombre",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _mainCurrency,
                        decoration: InputDecoration(
                          labelText: "Moneda local",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                        items: ["Bs", "COP", "MXN", "€", "USD", "PEN", "ARS", "CLP"]
                            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _mainCurrency = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: b,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "Saldo en $_mainCurrency",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: u,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "Saldo en Dólares (\$)",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      if (n.text.isNotEmpty) {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _userName = n.text;
                          _initialMain = _parseAmount(b.text);
                          _initialSec = _parseAmount(u.text);
                          _isFirstTime = false;
                          _isAuthorized = true;
                          _showTutorial = true;
                        });
                        _save();
                        _updateRates();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "COMENZAR",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== PANTALLA DE BLOQUEO ====================

  Widget _lockScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, size: 80, color: Colors.black),
            const SizedBox(height: 20),
            const Text(
              "Ziro está bloqueada",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _authenticate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text("Desbloquear"),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PANTALLA PRINCIPAL ====================

  @override
  Widget build(BuildContext context) {
    if (_isFirstTime) return _buildSetup();
    if (_showTutorial) return _buildTutorial();
    if (!_isAuthorized) return _lockScreen();

    double availableMain = _initialMain;
    double availableSec = _initialSec;

    double spentMain = _entries.where((e) => e.type == 'gasto' && e.currency == _mainCurrency).fold(0.0, (s, e) => s + e.amount);
    double spentSec = _entries.where((e) => e.type == 'gasto' && e.currency == '\$').fold(0.0, (s, e) => s + e.amount);

    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: IndexedStack(
            index: _selectedTabIndex,
            children: [
              _mainView(availableMain, availableSec),
              _statsView(spentMain, spentSec),
              _settingsView(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        onTap: (index) {
          setState(() => _selectedTabIndex = index);
          HapticFeedback.lightImpact();
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey.shade400,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Inicio",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: "Estadísticas",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: "Ajustes",
          ),
        ],
      ),
    );
  }

  // ==================== VISTA PRINCIPAL ====================

  Widget _mainView(double main, double sec) {
    return CustomScrollView(
      slivers: [
        _buildSliverAppBar(),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildBalanceCards(main, sec),
                const SizedBox(height: 20),
                _buildQuickActions(),
                const SizedBox(height: 20),
                if (_currentGoal != null) ...[
                  _buildGoalCard(),
                  const SizedBox(height: 20),
                ],
                _buildEmergencyFundCard(),
                const SizedBox(height: 20),
                _buildSectionHeader(
                  title: "Últimos movimientos",
                  action: "Ver todos",
                  onTap: () => setState(() => _selectedTabIndex = 1),
                ),
                const SizedBox(height: 12),
                _buildRecentTransactions(),
                const SizedBox(height: 20),
                _buildTipCard(),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 100,
      floating: true,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.grey.shade50],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1A1A1A), Colors.black],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            _userName.isNotEmpty ? _userName[0].toUpperCase() : 'Z',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Hola, $_userName",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            "Bienvenido",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_mainCurrency == "Bs")
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "BCV ${_f.format(_dollarPriceBCV)}",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00A86B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "EUR ${_f.format(_euroPrice)}",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCards(double mainBalance, double secBalance) {
    return Row(
      children: [
        Expanded(
          child: TweenAnimationBuilder(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutQuad,
            builder: (context, double value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1A1A), Color(0xFF2C3E50)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Disponible",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet,
                          color: Colors.white.withOpacity(0.7),
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "$_mainCurrency ${_f.format(mainBalance)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_mainCurrency == "Bs") ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildMiniRateChip(
                          label: "EUR",
                          value: mainBalance / _euroPrice,
                          color: const Color(0xFF00A86B),
                        ),
                        const SizedBox(width: 8),
                        _buildMiniRateChip(
                          label: "USD",
                          value: mainBalance / _dollarPriceBCV,
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TweenAnimationBuilder(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutQuad,
            builder: (context, double value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2C3E50), Color(0xFF3498DB)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Dólares",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.attach_money,
                          color: Colors.white.withOpacity(0.7),
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "\$ ${_f.format(secBalance)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniRateChip({required String label, required double value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        "$label: ${_f.format(value)}",
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Acciones rápidas",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildActionButton(
                icon: Icons.add_circle_outline,
                label: "Ingreso",
                color: Colors.green,
                onTap: () => _entryDialog('ingreso'),
              ),
              _buildActionButton(
                icon: Icons.remove_circle_outline,
                label: "Gasto",
                color: Colors.red,
                onTap: () => _entryDialog('gasto'),
              ),
              _buildActionButton(
                icon: Icons.savings_outlined,
                label: "Ahorro",
                color: Colors.blue,
                onTap: () => _entryDialog('ahorro'),
              ),
              _buildActionButton(
                icon: Icons.stars_outlined,
                label: "Meta",
                color: Colors.purple,
                onTap: _setGoalDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard() {
    double progress = (_currentGoal!.savedAmount /
        (_currentGoal!.targetAmount > 0 ? _currentGoal!.targetAmount : 1))
        .clamp(0.0, 1.0);

    return GestureDetector(
      onTap: _withdrawGoalDialog,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.purple.shade50, Colors.blue.shade50],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.purple.shade100.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _currentGoal!.imagePath.isNotEmpty
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(_currentGoal!.imagePath),
                      fit: BoxFit.cover,
                    ),
                  )
                      : const Icon(
                    Icons.emoji_events_outlined,
                    color: Colors.purple,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentGoal!.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${_currentGoal!.currency} ${_f.format(_currentGoal!.savedAmount)} de ${_f.format(_currentGoal!.targetAmount)}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${(progress * 100).toInt()}%",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.5),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.purple),
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyFundCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.shield_outlined,
              color: Colors.red.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Fondo de Emergencia",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "$_mainCurrency ${_f.format(_emergencyFund)}",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: Colors.orange.shade700,
                ),
                onPressed: _emergencyFund > 0 ? _withdrawEmergencyDialog : null,
                tooltip: "Retirar de emergencia",
              ),
              IconButton(
                icon: Icon(
                  Icons.add_circle_outline,
                  color: Colors.red.shade700,
                ),
                onPressed: _emergencyDialog,
                tooltip: "Agregar al fondo",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.tips_and_updates,
              size: 20,
              color: Colors.blueGrey.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Limpia tu historial cada 30 días para mantener todo organizado",
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String action,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        GestureDetector(
          onTap: onTap,
          child: Text(
            action,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactions() {
    List<Entry> recent = _entries.take(5).toList();

    if (recent.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              "No hay movimientos",
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Usa las acciones rápidas para agregar",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recent.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final e = recent[index];
        return _buildTransactionTile(e);
      },
    );
  }

  Widget _buildTransactionTile(Entry entry) {
    Color categoryColor = _getCategoryColor(entry.category);
    bool isIncome = entry.type == 'ingreso';

    return GestureDetector(
      onTap: () => _editEntryDialog(entry),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: categoryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _catIcons[entry.category] ?? Icons.more_horiz,
                color: categoryColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.category,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: isIncome
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "${isIncome ? '+' : '-'} ${entry.currency} ${_f.format(entry.amount)}",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== FUNCIONES PARA RESUMEN MENSUAL ====================

  String _getCurrentMonth() {
    return DateFormat('MMMM yyyy', 'es').format(DateTime.now());
  }

  double _getCurrentMonthIncome() {
    final now = DateTime.now();
    return _entries
        .where((e) => e.type == 'ingreso' && _isSameMonth(DateTime.parse(e.id), now))
        .fold(0.0, (sum, e) => sum + _convertToMainCurrency(e));
  }

  double _getCurrentMonthExpenses() {
    final now = DateTime.now();
    return _entries
        .where((e) => e.type == 'gasto' && _isSameMonth(DateTime.parse(e.id), now))
        .fold(0.0, (sum, e) => sum + _convertToMainCurrency(e));
  }

  double _getCurrentMonthSavings() {
    final now = DateTime.now();
    return _entries
        .where((e) => e.type == 'ahorro' && _isSameMonth(DateTime.parse(e.id), now))
        .fold(0.0, (sum, e) => sum + _convertToMainCurrency(e));
  }

  bool _isSameMonth(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month;
  }

  double _convertToMainCurrency(Entry entry) {
    if (entry.currency == _mainCurrency) {
      return entry.amount;
    } else if (entry.currency == "\$") {
      return entry.amount * _dollarPriceBCV;
    } else if (entry.currency == "€") {
      return entry.amount * _euroPrice;
    } else {
      return entry.amount;
    }
  }

  Map<String, double> _getCurrentMonthExpensesByCategory() {
    final now = DateTime.now();
    Map<String, double> result = {};

    for (var entry in _entries.where((e) => e.type == 'gasto' && _isSameMonth(DateTime.parse(e.id), now))) {
      double amount = _convertToMainCurrency(entry);
      result[entry.category] = (result[entry.category] ?? 0) + amount;
    }

    return result;
  }

  // ==================== VISTA DE ESTADÍSTICAS ====================

  Widget _statsView(double sm, double ss) {
    double monthlyIncome = _getCurrentMonthIncome();
    double monthlyExpenses = _getCurrentMonthExpenses();
    double monthlySavings = _getCurrentMonthSavings();
    Map<String, double> monthlyExpensesByCategory = _getCurrentMonthExpensesByCategory();

    return ListView(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 40),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                _getCurrentMonth().toUpperCase(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade900, Colors.purple.shade800],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_upward, color: Colors.green, size: 16),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("Ingresos del mes", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                  Text(
                    "$_mainCurrency ${_f.format(monthlyIncome)}",
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_downward, color: Colors.red, size: 16),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("Gastos del mes", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                  Text(
                    "$_mainCurrency ${_f.format(monthlyExpenses)}",
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 30),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.savings, color: Colors.amber, size: 16),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("Ahorro del mes", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                  Text(
                    "$_mainCurrency ${_f.format(monthlySavings)}",
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              if (monthlySavings == 0 && monthlyIncome > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue, size: 14),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Usa 'Ahorro' en acciones rápidas para guardar dinero",
                          style: TextStyle(color: Colors.blue, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (monthlyExpenses > monthlyIncome) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange, size: 14),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Has gastado más de lo que ingresaste",
                          style: TextStyle(color: Colors.orange, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (monthlyExpensesByCategory.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.pie_chart, size: 18, color: Colors.black54),
                    SizedBox(width: 8),
                    Text("¿En qué gastaste?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                ...monthlyExpensesByCategory.entries.map((entry) {
                  double percentage = (entry.value / monthlyExpenses) * 100;
                  Color categoryColor = _getCategoryColor(entry.key);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: categoryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                _catIcons[entry.key] ?? Icons.more_horiz,
                                color: categoryColor,
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 13))),
                            Text(
                              "$_mainCurrency ${_f.format(entry.value)}",
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 40,
                              child: Text(
                                "${percentage.toStringAsFixed(1)}%",
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: percentage / 100,
                            minHeight: 3,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(categoryColor),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Balance general", style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    "$_mainCurrency ${_f.format(_initialMain)}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total en dólares", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(
                    "\$ ${_f.format(_initialSec)}",
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ==================== VISTA DE AJUSTES ====================

  Widget _settingsView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 20),
        _buildSettingsHeader(),
        const SizedBox(height: 30),
        _buildSettingsSection(
          title: "Saldos",
          children: [
            _buildSettingsTile(
              icon: Icons.account_balance_wallet,
              title: "Ajustar saldos",
              subtitle: "$_mainCurrency ${_f.format(_initialMain)} | \$ ${_f.format(_initialSec)}",
              onTap: _addFundsDialog,
            ),
            _buildSettingsTile(
              icon: Icons.shield,
              title: "Fondo de emergencia",
              subtitle: "$_mainCurrency ${_f.format(_emergencyFund)}",
              onTap: _emergencyDialog,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildSettingsSection(
          title: "Preferencias",
          children: [
            _buildSettingsTile(
              icon: Icons.currency_exchange,
              title: "Moneda principal",
              subtitle: _mainCurrency,
              onTap: _showCurrencyDialog,
            ),
            _buildSettingsTile(
              icon: Icons.fingerprint,
              title: "Autenticación biométrica",
              subtitle: "Protege tu app con huella/rostro",
              onTap: _authenticate,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildSettingsSection(
          title: "Datos",
          children: [
            _buildSettingsTile(
              icon: Icons.upload_file,
              title: "Exportar datos",
              subtitle: "Guardar copia de seguridad",
              onTap: _exportData,
              iconColor: Colors.blue,
            ),
            _buildSettingsTile(
              icon: Icons.history,
              title: "Limpiar historial",
              subtitle: "Eliminar todos los movimientos",
              onTap: _clearHistoryDialog,
              iconColor: Colors.red,
            ),
            _buildSettingsTile(
              icon: Icons.delete_forever,
              title: "Resetear app",
              subtitle: "Borrar todos los datos",
              onTap: _resetAppDialog,
              iconColor: Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildSettingsSection(
          title: "Legal",
          children: [
            _buildSettingsTile(
              icon: Icons.privacy_tip,
              title: "Política de privacidad",
              subtitle: "Cómo protegemos tus datos",
              onTap: _showPrivacyPolicy,
              iconColor: Colors.grey,
            ),
          ],
        ),
        const SizedBox(height: 30),
        Center(
          child: Text(
            "Ziro v2.4",
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsHeader() {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A1A), Colors.black],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.settings, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Ajustes", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text("Personaliza tu experiencia", style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = Colors.black,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  // ==================== FUNCIONES GDPR ====================

  Future<void> _exportData() async {
    try {
      final exportData = {
        'appName': 'Ziro',
        'version': '2.4.0',
        'exportDate': DateTime.now().toIso8601String(),
        'userData': {
          'userName': _userName,
          'mainCurrency': _mainCurrency,
          'initialMain': _initialMain,
          'initialSec': _initialSec,
          'emergencyFund': _emergencyFund,
          'dollarRates': {
            'BCV': _dollarPriceBCV,
            'Euro': _euroPrice,
          },
        },
        'entries': _entries.map((e) => e.toMap()).toList(),
        'goal': _currentGoal?.toMap(),
      };

      final jsonString = jsonEncode(exportData);
      final tempDir = await getTemporaryDirectory();
      final fileName = 'ziro_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Exportación de datos de Ziro - ${DateTime.now().toLocal()}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos exportados correctamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar: $e')),
      );
    }
  }

  void _showPrivacyPolicy() async {
    final Uri url = Uri.parse('https://jeroguez.github.io/ziro-privacy-policy/privacy_policy.html');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la política de privacidad'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==================== DIÁLOGOS COMPLETOS ====================

  void _entryDialog(String type) {
    final t = TextEditingController();
    final a = TextEditingController();
    String selCat = "Otros";
    String selCurr = _mainCurrency;
    String source = "Sueldo";
    bool convertOnFly = false;

    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: StatefulBuilder(
          builder: (c, setS) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: type == 'ingreso' ? Colors.green.withOpacity(0.1) : type == 'gasto' ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        type == 'ingreso' ? Icons.add_circle_outline : type == 'gasto' ? Icons.remove_circle_outline : Icons.savings_outlined,
                        color: type == 'ingreso' ? Colors.green : type == 'gasto' ? Colors.red : Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Nuevo ${type == 'ingreso' ? 'Ingreso' : type == 'gasto' ? 'Gasto' : 'Ahorro'}",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: t,
                  decoration: InputDecoration(
                    labelText: "Concepto",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: a,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Monto",
                    prefixText: "$selCurr ",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selCurr,
                    underline: const SizedBox(),
                    items: [_mainCurrency, "\$"]
                        .map((v) => DropdownMenuItem(value: v, child: Text("Moneda: $v")))
                        .toList(),
                    onChanged: (v) => setS(() => selCurr = v!),
                  ),
                ),
                if (_mainCurrency == "Bs" && (selCurr != _mainCurrency))
                  SwitchListTile(
                    title: const Text("Usar tasa oficial", style: TextStyle(fontSize: 13)),
                    subtitle: selCurr == "\$"
                        ? Text("1 USD = $_dollarPriceBCV Bs", style: const TextStyle(fontSize: 11))
                        : const Text(""),
                    value: convertOnFly,
                    onChanged: (v) => setS(() => convertOnFly = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                if (type == 'gasto')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selCat,
                      underline: const SizedBox(),
                      items: _catIcons.keys.map((k) {
                        return DropdownMenuItem(
                          value: k,
                          child: Row(
                            children: [
                              Icon(_catIcons[k], size: 16, color: _getCategoryColor(k)),
                              const SizedBox(width: 8),
                              Text(k),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setS(() => selCat = v!),
                    ),
                  ),
                if (type == 'ahorro')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: source,
                      underline: const SizedBox(),
                      items: ["Sueldo", "Externo"]
                          .map((v) => DropdownMenuItem(value: v, child: Text("Origen: $v")))
                          .toList(),
                      onChanged: (v) => setS(() => source = v!),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text("Cancelar"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          double val = _parseAmount(a.text);
                          if (t.text.isNotEmpty && val > 0) {
                            double finalVal = val;
                            String finalCurr = selCurr;
                            if (convertOnFly) {
                              if (selCurr == "\$") {
                                finalVal = val * _dollarPriceBCV;
                                finalCurr = _mainCurrency;
                              } else if (selCurr == _mainCurrency) {
                                finalVal = val / _dollarPriceBCV;
                                finalCurr = "\$";
                              }
                            }
                            setState(() {
                              if (finalCurr == _mainCurrency) {
                                if (type == 'ingreso') _initialMain += finalVal;
                                if (type == 'gasto') _initialMain -= finalVal;
                                if (type == 'ahorro' && source == "Sueldo")
                                  _initialMain -= finalVal;
                              } else if (finalCurr == "\$") {
                                if (type == 'ingreso') _initialSec += finalVal;
                                if (type == 'gasto') _initialSec -= finalVal;
                                if (type == 'ahorro' && source == "Sueldo")
                                  _initialSec -= finalVal;
                              }

                              double histAmount = (type == 'ahorro' && source == "Externo") ? 0.0 : finalVal;
                              _entries.insert(
                                0,
                                Entry(
                                  id: DateTime.now().toString(),
                                  title: t.text,
                                  amount: histAmount,
                                  type: type,
                                  category: selCat,
                                  currency: finalCurr,
                                ),
                              );

                              if (type == 'ahorro' && _currentGoal != null) {
                                double valGoal = (finalCurr == _currentGoal!.currency)
                                    ? finalVal
                                    : (finalCurr == _mainCurrency
                                    ? finalVal / _dollarPriceBCV
                                    : finalVal * _dollarPriceBCV);
                                _currentGoal!.savedAmount += valGoal;
                              }
                            });
                            _save();
                            Navigator.pop(c);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Guardar"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editEntryDialog(Entry entry) {
    final t = TextEditingController(text: entry.title);
    final a = TextEditingController(text: entry.amount.toString());

    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.edit, color: Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  const Text("Editar registro", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: t,
                decoration: InputDecoration(
                  labelText: "Concepto",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: a,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Monto",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _entries.removeWhere((item) => item.id == entry.id);
                        });
                        _save();
                        Navigator.pop(c);
                      },
                      child: const Text("ELIMINAR", style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        double nuevoMonto = _parseAmount(a.text);
                        double diferencia = nuevoMonto - entry.amount;
                        setState(() {
                          if (entry.type == 'gasto') {
                            if (entry.currency == _mainCurrency) {
                              _initialMain -= diferencia;
                            } else {
                              _initialSec -= diferencia;
                            }
                          } else if (entry.type == 'ingreso') {
                            if (entry.currency == _mainCurrency) {
                              _initialMain += diferencia;
                            } else {
                              _initialSec += diferencia;
                            }
                          }
                          entry.title = t.text;
                          entry.amount = nuevoMonto;
                        });
                        _save();
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Guardar"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _withdrawGoalDialog() {
    if (_currentGoal == null) return;
    final a = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sentiment_very_dissatisfied, size: 50, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                "¿Retirar de ${_currentGoal!.name}?",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "Me decepcionas, porque vas a sacar plata para cosas sin sentido...",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: a,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Monto en ${_currentGoal!.currency}",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancelar"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        double val = _parseAmount(a.text);
                        if (val > 0 && val <= _currentGoal!.savedAmount) {
                          setState(() {
                            _currentGoal!.savedAmount -= val;
                            if (_currentGoal!.currency == _mainCurrency) {
                              _initialMain += val;
                            } else {
                              _initialSec += val;
                            }
                            _entries.insert(
                              0,
                              Entry(
                                id: DateTime.now().toString(),
                                title: "Retiro de Meta: ${_currentGoal!.name}",
                                amount: val,
                                type: 'ingreso',
                                category: "Otros",
                                currency: _currentGoal!.currency,
                              ),
                            );
                          });
                          _save();
                          Navigator.pop(c);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Retirar"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setGoalDialog() async {
    final n = TextEditingController();
    final m = TextEditingController();
    String tempCurr = "\$";
    String imgPath = "";

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.emoji_events_outlined, color: Colors.purple),
                    ),
                    const SizedBox(width: 12),
                    const Text("Nueva meta", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: n,
                  decoration: InputDecoration(
                    labelText: "¿Qué buscas?",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: m,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Monto total",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: tempCurr,
                    underline: const SizedBox(),
                    items: ["\$", _mainCurrency]
                        .map((e) => DropdownMenuItem(value: e, child: Text("Moneda meta: $e")))
                        .toList(),
                    onChanged: (v) => setS(() => tempCurr = v!),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.image),
                  label: const Text("Agregar imagen"),
                  onPressed: () async {
                    final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (file != null) setS(() => imgPath = file.path);
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text("Cancelar"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (n.text.isNotEmpty && m.text.isNotEmpty) {
                            setState(() {
                              _currentGoal = Goal(
                                name: n.text,
                                targetAmount: _parseAmount(m.text),
                                imagePath: imgPath,
                                currency: tempCurr,
                              );
                            });
                            _save();
                            Navigator.pop(c);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Crear"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addFundsDialog() {
    final m = TextEditingController(text: _initialMain.toString());
    final d = TextEditingController(text: _initialSec.toString());

    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.account_balance_wallet, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  const Text("Ajustar saldos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "Modifica directamente tu disponibilidad:",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: m,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Saldo en $_mainCurrency",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: d,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Saldo en Dólares (\$)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancelar"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initialMain = _parseAmount(m.text);
                          _initialSec = _parseAmount(d.text);
                        });
                        _save();
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Guardar"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== DIÁLOGOS DE EMERGENCIA ====================

  void _emergencyDialog() {
    final a = TextEditingController();
    String source = "Saldo actual";
    String currency = _mainCurrency;

    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: StatefulBuilder(
          builder: (c, setS) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.shield, color: Colors.red),
                    ),
                    const SizedBox(width: 12),
                    const Text("Fondo de emergencia", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: a,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Monto",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: currency,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                        value: _mainCurrency,
                        child: Row(
                          children: [
                            Icon(Icons.currency_exchange, size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(_mainCurrency),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: "\$",
                        child: Row(
                          children: [
                            Icon(Icons.attach_money, size: 18, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            const Text("USD \$"),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (v) => setS(() => currency = v!),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: source,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                        value: "Saldo actual",
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet, size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text("De mi saldo actual (${currency == _mainCurrency ? _f.format(_initialMain) : _f.format(_initialSec)} $currency)"),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: "Externo",
                        child: Row(
                          children: [
                            Icon(Icons.attach_money, size: 18, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            const Text("Dinero externo (no afecta saldo)"),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (v) => setS(() => source = v!),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: source == "Saldo actual" ? Colors.blue.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        source == "Saldo actual" ? Icons.info_outline : Icons.check_circle_outline,
                        size: 16,
                        color: source == "Saldo actual" ? Colors.blue.shade700 : Colors.green.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          source == "Saldo actual"
                              ? "Se restará de tu saldo en $currency"
                              : "Se agregará directamente sin afectar tu saldo",
                          style: TextStyle(
                            fontSize: 12,
                            color: source == "Saldo actual" ? Colors.blue.shade700 : Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          setState(() => _emergencyFund = 0);
                          _save();
                          Navigator.pop(c);
                        },
                        child: const Text("LIMPIAR", style: TextStyle(color: Colors.red)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          double monto = _parseAmount(a.text);
                          if (monto > 0) {
                            setState(() {
                              double montoEnMain = monto;
                              if (currency == "\$") {
                                montoEnMain = monto * _dollarPriceBCV;
                              }

                              if (source == "Saldo actual") {
                                bool hasEnough = false;
                                if (currency == _mainCurrency && _initialMain >= monto) {
                                  _initialMain -= monto;
                                  hasEnough = true;
                                } else if (currency == "\$" && _initialSec >= monto) {
                                  _initialSec -= monto;
                                  hasEnough = true;
                                }

                                if (hasEnough) {
                                  _entries.insert(
                                    0,
                                    Entry(
                                      id: DateTime.now().toString(),
                                      title: "Transferencia a Fondo de Emergencia",
                                      amount: monto,
                                      type: 'gasto',
                                      category: "Emergencia",
                                      currency: currency,
                                    ),
                                  );
                                } else {
                                  Navigator.pop(c);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("No tienes suficiente saldo en $currency"),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                              } else {
                                _entries.insert(
                                  0,
                                  Entry(
                                    id: DateTime.now().toString(),
                                    title: "Aporte externo a Fondo de Emergencia",
                                    amount: monto,
                                    type: 'ingreso',
                                    category: "Emergencia",
                                    currency: currency,
                                  ),
                                );
                              }

                              _emergencyFund += montoEnMain;
                            });
                            _save();
                            Navigator.pop(c);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Agregar"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _withdrawEmergencyDialog() {
    final a = TextEditingController();
    String currency = _mainCurrency;

    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: StatefulBuilder(
          builder: (c, setS) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.warning_amber, color: Colors.orange),
                    ),
                    const SizedBox(width: 12),
                    const Text("Retirar de Emergencia", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  "¿Estás seguro? Esto solo debe usarse en situaciones de EMERGENCIA REAL.",
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: a,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Monto a retirar",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: currency,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                        value: _mainCurrency,
                        child: Row(
                          children: [
                            Icon(Icons.currency_exchange, size: 18, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(_mainCurrency),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: "\$",
                        child: Row(
                          children: [
                            Icon(Icons.attach_money, size: 18, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            const Text("USD \$"),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (v) => setS(() => currency = v!),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text("Cancelar"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          double monto = _parseAmount(a.text);

                          double montoEnMain = monto;
                          if (currency == "\$") {
                            montoEnMain = monto * _dollarPriceBCV;
                          }

                          if (monto > 0 && montoEnMain <= _emergencyFund) {
                            setState(() {
                              _emergencyFund -= montoEnMain;

                              if (currency == _mainCurrency) {
                                _initialMain += monto;
                              } else {
                                _initialSec += monto;
                              }

                              _entries.insert(
                                0,
                                Entry(
                                  id: DateTime.now().toString(),
                                  title: "Retiro de Fondo de Emergencia",
                                  amount: monto,
                                  type: 'ingreso',
                                  category: "Emergencia",
                                  currency: currency,
                                ),
                              );
                            });
                            _save();
                            Navigator.pop(c);
                          } else {
                            Navigator.pop(c);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Monto inválido o excede el fondo disponible (${_f.format(_emergencyFund)} $_mainCurrency)"),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Retirar"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearHistoryDialog() {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning, size: 50, color: Colors.orange),
              const SizedBox(height: 16),
              const Text("¿Limpiar historial?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                "Esta acción eliminará todos los movimientos pero mantendrá tus saldos actuales.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancelar"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _entries.clear());
                        _save();
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Limpiar"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetAppDialog() {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning, size: 50, color: Colors.red),
              const SizedBox(height: 16),
              const Text("¿Resetear la app?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                "Se borrarán TODOS tus datos. Esta acción no se puede deshacer.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancelar"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final p = await SharedPreferences.getInstance();
                        await p.clear();
                        setState(() {
                          _isFirstTime = true;
                          _isAuthorized = false;
                          _entries.clear();
                          _currentGoal = null;
                          _userName = "";
                          _initialMain = 0;
                          _initialSec = 0;
                          _emergencyFund = 0;
                        });
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Resetear"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCurrencyDialog() {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Cambiar moneda principal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...["Bs", "COP", "MXN", "€", "USD", "PEN", "ARS", "CLP"]
                  .map((currency) => ListTile(
                title: Text(currency),
                leading: Radio<String>(
                  value: currency,
                  groupValue: _mainCurrency,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _mainCurrency = v);
                      _save();
                      Navigator.pop(c);
                    }
                  },
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Comida': return Colors.orange;
      case 'Transporte': return Colors.blue;
      case 'Servicios': return Colors.purple;
      case 'Ocio': return Colors.pink;
      case 'Salud': return Colors.green;
      case 'Educación': return Colors.teal;
      case 'Emergencia': return Colors.red;
      default: return Colors.grey;
    }
  }

  // ==================== ONBOARDING TUTORIAL ====================

  Widget _buildTutorial() {
    final PageController _pageController = PageController();
    int _currentPage = 0;

    return StatefulBuilder(
      builder: (context, setState) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(10, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 12 : 8,
                        height: _currentPage == index ? 12 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? Colors.black : Colors.grey.shade300,
                          shape: BoxShape.circle,
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    children: [
                      _buildTutorialPage(
                        icon: Icons.account_balance_wallet,
                        title: "¿QUÉ ES ZIRO?",
                        description: "Ziro es tu asistente financiero personal. Te ayuda a controlar tus ingresos, gastos y ahorros de manera simple y efectiva.\n\n✅ Lleva el control de tu dinero\n✅ Organiza tus finanzas\n✅ Alcanza tus metas",
                        action: "Tu aliado financiero",
                        color: Colors.black,
                      ),
                      _buildTutorialPage(
                        icon: Icons.attach_money,
                        title: "TUS SALDOS",
                        description: "La app muestra tu dinero en dos monedas:\n\n💰 ${_mainCurrency}: Tu moneda local\n💵 Dólares (\$): Para operaciones en USD\n\n📊 Los precios del dólar (BCV) y Euro se actualizan automáticamente desde internet cuando estás en Venezuela.",
                        action: "Siempre actualizado",
                        color: Colors.blue.shade900,
                      ),
                      _buildTutorialPage(
                        icon: Icons.bolt,
                        title: "ACCIONES RÁPIDAS",
                        description: "Con 4 botones puedes hacer todo:\n\n💰 INGRESO: Cuando recibes dinero (sueldo, regalos, etc.)\n💸 GASTO: Cuando pagas algo (comida, transporte, etc.)\n🏦 AHORRO: Para tu meta de ahorro\n🎯 META: Crea objetivos financieros",
                        action: "Registra en segundos",
                        color: Colors.green.shade800,
                      ),
                      _buildTutorialPage(
                        icon: Icons.emoji_events,
                        title: "METAS DE AHORRO",
                        description: "¿Quieres comprar algo especial?\n\n✅ Crea una meta con foto\n✅ Ahorra poco a poco\n✅ Ve tu progreso en %\n✅ Celebra cuando la cumplas\n\n💡 Puedes ahorrar desde tu saldo o con dinero externo",
                        action: "Convierte sueños en realidad",
                        color: Colors.purple,
                      ),
                      _buildTutorialPage(
                        icon: Icons.shield,
                        title: "FONDO DE EMERGENCIA",
                        description: "Tu colchón financiero para imprevistos:\n\n🛡️ AGREGAR: Puedes elegir:\n   • Desde tu saldo (se resta automáticamente)\n   • Dinero externo (no afecta tu saldo)\n   • En Bs o Dólares (se convierte solo)\n\n⚠️ RETIRAR: Solo para EMERGENCIAS REALES\n   • Médicas, reparaciones urgentes\n   • Devuelve el dinero a tu saldo",
                        action: "Prepárate para lo inesperado",
                        color: Colors.red,
                      ),
                      _buildTutorialPage(
                        icon: Icons.history,
                        title: "HISTORIAL",
                        description: "Cada movimiento queda registrado:\n\n📝 Toca cualquier registro para:\n   • Editar concepto o monto\n   • Eliminar si te equivocaste\n\n🔄 Los últimos 5 movimientos se ven en inicio\n📊 En estadísticas ves el mes completo",
                        action: "Nunca pierdas la pista",
                        color: Colors.orange,
                      ),
                      _buildTutorialPage(
                        icon: Icons.bar_chart,
                        title: "ESTADÍSTICAS DEL MES",
                        description: "Análisis completo de tu mes:\n\n📈 Ingresos totales del mes\n📉 Gastos por categoría\n💰 Ahorro real (solo movimientos 'ahorro')\n\n🎯 Desglose por categorías:\n   • Comida 🍔\n   • Transporte 🚗\n   • Servicios 💡\n   • Ocio 🎮\n   • Salud 🏥\n   • Educación 📚\n   • Emergencia ⚠️",
                        action: "Descubre tus hábitos",
                        color: Colors.green,
                      ),
                      _buildTutorialPage(
                        icon: Icons.calendar_month,
                        title: "RESUMEN MENSUAL",
                        description: "En la pestaña de estadísticas encontrarás:\n\n✅ Ingresos vs Gastos del mes\n✅ Ahorro acumulado\n✅ Alerta si gastaste más de lo que ingresaste\n✅ Balance general total\n\n💡 Consejo: Revisa tus estadísticas cada mes para mejorar tus finanzas",
                        action: "Control total mensual",
                        color: Colors.teal,
                      ),
                      _buildTutorialPage(
                        icon: Icons.currency_exchange,
                        title: "CONVERSOR AUTOMÁTICO",
                        description: "Cuando agregas dinero en dólares o euros:\n\n💱 Se convierte automáticamente a $_mainCurrency usando la tasa oficial\n\n🔄 El fondo de emergencia siempre se guarda en $_mainCurrency para consistencia\n\n📊 Las estadísticas convierten todo a $_mainCurrency para comparar correctamente",
                        action: "Todo en una sola moneda",
                        color: Colors.amber.shade800,
                      ),
                      _buildTutorialPage(
                        icon: Icons.settings,
                        title: "AJUSTES Y SEGURIDAD",
                        description: "Personaliza tu experiencia:\n\n🔒 Autenticación biométrica (huella/rostro)\n💰 Ajustar saldos manualmente\n🏦 Modificar fondo de emergencia\n🌎 Cambiar moneda principal\n🧹 Limpiar historial\n🔄 Resetear app (borra todo)\n📤 Exportar datos (GDPR)\n🔐 Política de privacidad",
                        action: "Tú controlas Ziro",
                        color: Colors.grey.shade800,
                      ),
                      _buildLastTutorialPage(_pageController),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTutorialPage({
    required IconData icon,
    required String title,
    required String description,
    required String action,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 70, color: color),
          ),
          const SizedBox(height: 40),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              description,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade800, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: color, size: 16),
                const SizedBox(width: 8),
                Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastTutorialPage(PageController pageController) {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A1A), Colors.black],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rocket_launch, size: 80, color: Colors.white),
          ),
          const SizedBox(height: 40),
          const Text(
            "¡YA ESTÁS LISTO!",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              children: [
                const Text(
                  "Ziro te ayudará a:",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.green),
                ),
                const SizedBox(height: 16),
                _buildBenefitItem(Icons.trending_up, "Saber dónde se va tu dinero"),
                _buildBenefitItem(Icons.savings, "Ahorrar para tus metas"),
                _buildBenefitItem(Icons.security, "Tener un fondo de emergencia"),
                _buildBenefitItem(Icons.insights, "Entender tus hábitos financieros"),
              ],
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _showTutorial = false;
                _tutorialCompleted = true;
              });
              _save();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              minimumSize: const Size(250, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 5,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("COMENZAR", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(width: 10),
                Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.green.shade700),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }
}