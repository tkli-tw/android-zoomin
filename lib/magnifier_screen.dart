import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

enum HandMode { left, right }

class MagnifierScreen extends StatefulWidget {
  const MagnifierScreen({super.key});

  @override
  State<MagnifierScreen> createState() => _MagnifierScreenState();
}

class _MagnifierScreenState extends State<MagnifierScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  Object? _cameraError;
  HandMode _handMode = HandMode.left;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  bool _torchOn = false;
  bool _torchSupported = true;
  bool _capturing = false;

  bool get _cameraReady => _controller?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    if (_controller != null) return;
    if (mounted) setState(() => _cameraError = null);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('找不到可用的相機');

      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      await controller.initialize();
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final initialZoom = 1.0.clamp(minZoom, maxZoom).toDouble();
      await controller.setZoomLevel(initialZoom);
      await controller.setFlashMode(FlashMode.off);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _camera = camera;
        _controller = controller;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _zoom = initialZoom;
        _torchOn = false;
        _torchSupported = true;
      });
    } on CameraException catch (error) {
      _setCameraError(_cameraErrorMessage(error));
    } catch (error) {
      _setCameraError(error);
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    _torchOn = false;
    await controller.dispose();
    if (mounted) setState(() {});
  }

  void _setCameraError(Object error) {
    if (!mounted) return;
    setState(() {
      _controller = null;
      _cameraError = error;
    });
  }

  String _cameraErrorMessage(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' => '需要相機權限才能使用放大鏡',
      'CameraAccessDeniedWithoutPrompt' => '相機權限已被拒絕，請到系統設定中開啟',
      'CameraAccessRestricted' => '這台裝置限制了相機存取',
      _ => error.description ?? '無法啟動相機',
    };
  }

  Future<void> _changeZoom(bool zoomIn) async {
    final controller = _controller;
    if (controller == null || !_cameraReady) return;

    final factor = zoomIn ? 1.25 : 1 / 1.25;
    final next = (_zoom * factor).clamp(_minZoom, _maxZoom).toDouble();
    if ((next - _zoom).abs() < 0.001) return;

    try {
      await controller.setZoomLevel(next);
      if (mounted) setState(() => _zoom = next);
    } on CameraException catch (error) {
      _showMessage(error.description ?? '無法調整倍率');
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !_cameraReady || !_torchSupported) return;

    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } on CameraException {
      if (mounted) {
        setState(() {
          _torchSupported = false;
          _torchOn = false;
        });
      }
      _showMessage('這個鏡頭不支援手電筒');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !_cameraReady || _capturing) return;

    setState(() => _capturing = true);
    try {
      final image = await controller.takePicture();
      final hasAccess =
          await Gal.hasAccess(toAlbum: true) ||
          await Gal.requestAccess(toAlbum: true);
      if (!hasAccess) {
        _showMessage('沒有儲存圖片的權限');
        return;
      }
      await Gal.putImage(image.path, album: 'Zoomin');
      _showMessage('已保存到 Zoomin 相簿');
    } on GalException catch (error) {
      _showMessage(switch (error.type) {
        GalExceptionType.accessDenied => '沒有保存圖片的權限',
        GalExceptionType.notEnoughSpace => '儲存空間不足',
        GalExceptionType.notSupportedFormat => '不支援這個圖片格式',
        GalExceptionType.unexpected => '保存圖片時發生錯誤',
      });
    } on CameraException catch (error) {
      _showMessage(error.description ?? '截圖失敗');
    } catch (_) {
      _showMessage('截圖失敗');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _toggleHandMode() {
    setState(() {
      _handMode = _handMode == HandMode.left ? HandMode.right : HandMode.left;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black, child: _buildCameraContent()),
          SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _HandModeButton(
                      mode: _handMode,
                      onPressed: _toggleHandMode,
                    ),
                  ),
                ),
                if (_cameraReady)
                  _AdaptiveToolBar(
                    handMode: _handMode,
                    canZoomIn: _zoom < _maxZoom - 0.001,
                    canZoomOut: _zoom > _minZoom + 0.001,
                    torchOn: _torchOn,
                    torchSupported: _torchSupported,
                    capturing: _capturing,
                    onZoomIn: () => _changeZoom(true),
                    onZoomOut: () => _changeZoom(false),
                    onCapture: _capture,
                    onToggleTorch: _toggleTorch,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraContent() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return Center(
        child: CameraPreview(controller, key: ValueKey(_camera?.name)),
      );
    }

    final error = _cameraError;
    if (error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _CameraErrorView(
      message: error.toString(),
      onRetry: _initializeCamera,
    );
  }
}

class _AdaptiveToolBar extends StatelessWidget {
  const _AdaptiveToolBar({
    required this.handMode,
    required this.canZoomIn,
    required this.canZoomOut,
    required this.torchOn,
    required this.torchSupported,
    required this.capturing,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCapture,
    required this.onToggleTorch,
  });

  final HandMode handMode;
  final bool canZoomIn;
  final bool canZoomOut;
  final bool torchOn;
  final bool torchSupported;
  final bool capturing;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCapture;
  final VoidCallback onToggleTorch;

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final actions = <Widget>[
      _ToolButton(
        key: const Key('zoom-in'),
        icon: Icons.add,
        label: '放大',
        onPressed: canZoomIn ? onZoomIn : null,
      ),
      _ToolButton(
        key: const Key('zoom-out'),
        icon: Icons.remove,
        label: '縮小',
        onPressed: canZoomOut ? onZoomOut : null,
      ),
      _ToolButton(
        key: const Key('capture'),
        icon: capturing ? Icons.hourglass_top : Icons.camera_alt_rounded,
        label: capturing ? '保存中' : '截圖',
        onPressed: capturing ? null : onCapture,
      ),
      _ToolButton(
        key: const Key('torch'),
        icon: torchOn ? Icons.flashlight_on : Icons.flashlight_off,
        label: torchOn ? '關燈' : '補光',
        selected: torchOn,
        onPressed: torchSupported ? onToggleTorch : null,
      ),
    ];

    if (isPortrait) {
      final displayed = handMode == HandMode.left
          ? actions
          : actions.reversed.toList(growable: false);
      return Align(
        alignment: handMode == HandMode.left
            ? Alignment.bottomLeft
            : Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _ToolSurface(
            child: Row(mainAxisSize: MainAxisSize.min, children: displayed),
          ),
        ),
      );
    }

    return Align(
      alignment: handMode == HandMode.left
          ? Alignment.bottomLeft
          : Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _ToolSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: actions.reversed.toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _ToolSurface extends StatelessWidget {
  const _ToolSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xDD151515),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        color: color,
        disabledColor: Colors.white30,
        iconSize: 30,
        padding: const EdgeInsets.all(14),
        icon: Icon(icon),
      ),
    );
  }
}

class _HandModeButton extends StatelessWidget {
  const _HandModeButton({required this.mode, required this.onPressed});

  final HandMode mode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isLeft = mode == HandMode.left;
    return FilledButton.tonalIcon(
      key: const Key('hand-mode'),
      onPressed: onPressed,
      icon: Icon(isLeft ? Icons.back_hand : Icons.front_hand),
      label: Text(isLeft ? '左手' : '右手'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xCC151515),
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 56),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('再試一次'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
