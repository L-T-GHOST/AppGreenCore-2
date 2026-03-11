import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/simulation_engine.dart';
import '../widgets/server_card.dart';
import '../widgets/cooling_controls.dart';
import 'simulation_page.dart';

class InputPage extends StatelessWidget {
  const InputPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: Column(
        children: [
          _TopBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                children: [
                  // Live metric row
                  _MetricsRow(),
                  const SizedBox(height: 20),
                  // Main input area — two column layout
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _ServerParametersCard()),
                            const SizedBox(width: 20),
                            Expanded(child: _CoolingSection()),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _ServerParametersCard(),
                          const SizedBox(height: 20),
                          _CoolingSection(),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  _RunSimulationButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top Bar ─────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1E),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF00D4FF).withOpacity(0.15)),
        ),
      ),
      child: Row(
        children: [
          // Logo / icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF00D4FF).withOpacity(0.4),
              ),
            ),
            child: const Icon(Icons.storage, color: Color(0xFF00D4FF), size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'DATA CENTER SIMULATOR',
                style: TextStyle(
                  color: Color(0xFF00D4FF),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              Text(
                'v1.0  |  3D Server Room Simulation',
                style: TextStyle(
                  color: Color(0xFF555577),
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          _PulsingDot(),
          const SizedBox(width: 8),
          const Text(
            'SYSTEM ONLINE',
            style: TextStyle(
              color: Color(0xFF00FF88),
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(
              const Color(0xFF00FF88),
              const Color(0xFF00FF88).withOpacity(0.3),
              _ctrl.value,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00FF88)
                    .withOpacity(0.5 * (1 - _ctrl.value)),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      );
}

// ─── Live Metrics Row ─────────────────────────────────────────────────────────
class _MetricsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();

    return Row(
      children: [
        MetricTile(
          label: 'EST. HEAT OUTPUT',
          value: '${engine.estimatedHeatOutput.toStringAsFixed(2)} kW',
          icon: Icons.local_fire_department,
          color: const Color(0xFFFF6B35),
        ),
        MetricTile(
          label: 'EST. ROOM TEMP',
          value: '${engine.estimatedRoomTemp.toStringAsFixed(1)} °C',
          icon: Icons.thermostat,
          color: _tempColor(engine.estimatedRoomTemp),
        ),
        MetricTile(
          label: 'TOTAL SERVER HEAT',
          value: engine.serverHeat.toStringAsFixed(1),
          icon: Icons.bolt,
          color: const Color(0xFFFFCC00),
        ),
        MetricTile(
          label: 'COOLING POWER',
          value:
              '${(engine.coolingModel.effectiveCooling * 100).toStringAsFixed(0)}%',
          icon: Icons.ac_unit,
          color: const Color(0xFF00D4FF),
        ),
      ],
    );
  }

  Color _tempColor(double t) {
    if (t < 24) return const Color(0xFF00D4FF);
    if (t < 28) return const Color(0xFF00FF88);
    if (t < 32) return const Color(0xFFFFCC00);
    return const Color(0xFFFF3333);
  }
}

// ─── Server Parameters Card ──────────────────────────────────────────────────
class _ServerParametersCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();

    return DashboardCard(
      title: 'SERVER PARAMETERS',
      icon: Icons.dns,
      accentColor: const Color(0xFF00FF88),
      children: [
        LabeledSlider(
          label: 'CPU UTILIZATION',
          value: engine.cpuUtilization,
          min: 0,
          max: 100,
          unit: '%',
          activeColor: const Color(0xFF00FF88),
          onChanged: engine.setCpu,
        ),
        LabeledSlider(
          label: 'NETWORK TRAFFIC',
          value: engine.networkTraffic,
          min: 0,
          max: 10,
          unit: 'Gbps',
          activeColor: const Color(0xFF00D4FF),
          onChanged: engine.setNetworkTraffic,
        ),
        // Temperature direct input row
        _TemperatureInput(engine: engine),
        const SizedBox(height: 12),
        LabeledSlider(
          label: 'POWER LOAD',
          value: engine.powerLoad,
          min: 0,
          max: 100,
          unit: '%',
          activeColor: const Color(0xFFFFCC00),
          onChanged: engine.setPowerLoad,
        ),
      ],
    );
  }
}

class _TemperatureInput extends StatefulWidget {
  final SimulationEngine engine;
  const _TemperatureInput({required this.engine});

  @override
  State<_TemperatureInput> createState() => _TemperatureInputState();
}

class _TemperatureInputState extends State<_TemperatureInput> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.engine.serverTemperature.toStringAsFixed(0),
    );
  }

  @override
  void didUpdateWidget(_TemperatureInput old) {
    super.didUpdateWidget(old);
    if (!_editing) {
      _ctrl.text = widget.engine.serverTemperature.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _tempColor(widget.engine.serverTemperature);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SERVER TEMPERATURE',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
            ),
            SizedBox(
              width: 110,
              height: 30,
              child: TextField(
                controller: _ctrl,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  suffixText: '°C',
                  suffixStyle: TextStyle(color: color, fontSize: 12),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: color.withOpacity(0.4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: color),
                  ),
                  filled: true,
                  fillColor: color.withOpacity(0.08),
                ),
                keyboardType: TextInputType.number,
                onTap: () => setState(() => _editing = true),
                onSubmitted: (v) {
                  setState(() => _editing = false);
                  final parsed = double.tryParse(v);
                  if (parsed != null) {
                    widget.engine.setServerTemperature(parsed.clamp(20, 95));
                  }
                },
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null) {
                    widget.engine.setServerTemperature(parsed.clamp(20, 95));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: color.withOpacity(0.15),
            thumbColor: color,
            overlayColor: color.withOpacity(0.15),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: widget.engine.serverTemperature,
            min: 20,
            max: 95,
            onChanged: (v) {
              widget.engine.setServerTemperature(v);
              if (!_editing) {
                _ctrl.text = v.toStringAsFixed(0);
              }
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Color _tempColor(double t) {
    if (t < 60) return const Color(0xFF00FF88);
    if (t < 75) return const Color(0xFFFFCC00);
    return const Color(0xFFFF3333);
  }
}

// ─── Cooling Section ─────────────────────────────────────────────────────────
class _CoolingSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CoolingControls(),
        const SizedBox(height: 20),
        _SimulationPreviewCard(),
      ],
    );
  }
}

class _SimulationPreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();

    return DashboardCard(
      title: 'SIMULATION PREVIEW',
      icon: Icons.bar_chart,
      accentColor: const Color(0xFF7B2FFF),
      children: [
        _BarRow(
          label: 'CPU Load',
          value: engine.cpuUtilization / 100,
          color: const Color(0xFF00FF88),
        ),
        _BarRow(
          label: 'Network Load',
          value: engine.networkTraffic / 10,
          color: const Color(0xFF00D4FF),
        ),
        _BarRow(
          label: 'Thermal Load',
          value: (engine.serverTemperature - 20) / 75,
          color: _tempColor(engine.serverTemperature),
        ),
        _BarRow(
          label: 'Power Draw',
          value: engine.powerLoad / 100,
          color: const Color(0xFFFFCC00),
        ),
        _BarRow(
          label: 'Cooling Active',
          value: engine.coolingModel.effectiveCooling,
          color: const Color(0xFF00D4FF),
          last: true,
        ),
      ],
    );
  }

  Color _tempColor(double t) {
    if (t < 60) return const Color(0xFF00FF88);
    if (t < 75) return const Color(0xFFFFCC00);
    return const Color(0xFFFF3333);
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double value; // 0-1
  final Color color;
  final bool last;

  const _BarRow({
    required this.label,
    required this.value,
    required this.color,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style:
                  const TextStyle(color: Color(0xFF888888), fontSize: 11),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E3A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.7), color],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${(v * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: color, fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Run Simulation Button ───────────────────────────────────────────────────
class _RunSimulationButton extends StatefulWidget {
  @override
  State<_RunSimulationButton> createState() => _RunSimulationButtonState();
}

class _RunSimulationButtonState extends State<_RunSimulationButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => GestureDetector(
        onTap: () => Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, anim, __) => const SimulationPage(),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: anim,
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 600),
          ),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0066AA), Color(0xFF00D4FF)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF)
                      .withOpacity(0.3 + 0.2 * _ctrl.value),
                  blurRadius: 20 + 10 * _ctrl.value,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.view_in_ar, color: Colors.white, size: 22),
                SizedBox(width: 12),
                Text(
                  'RUN SIMULATION',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
