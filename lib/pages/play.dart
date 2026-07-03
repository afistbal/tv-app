import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/global.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/mobad.dart';
import 'package:yogotv/states/user.dart';

class Play extends StatefulWidget {
  final int? id;
  final dynamic watchTo;

  const Play({super.key, this.id, this.watchTo});

  @override
  State<StatefulWidget> createState() {
    return _Play();
  }
}

String _watchToEpisodeId(dynamic watchTo) {
  if (watchTo is! Map) {
    return '';
  }
  return '${watchTo['episode_id'] ?? watchTo['ep_id'] ?? watchTo['epId'] ?? ''}'
      .trim();
}

class _Play extends State<Play> {
  late final String earnKey;
  PageController? _controller;
  dynamic _data;
  bool _loading = true;
  int _index = 0;
  bool _ui = true;

  @override
  void initState() {
    super.initState();
    earnKey =
        'video_earn_${DateTime.now().toIso8601String().substring(0, 10)}_${FirebaseAuth.instance.currentUser?.uid}';
    _loadData();
  }

  _loadData() async {
    final result = await api('movie/info', query: {'id': widget.id});
    if (result.c != 0) {
      return;
    }

    Global.sp.setBool('update_history', true);

    final earn = Global.sp.getInt(earnKey);
    if (earn == null) {
      Global.sp.setInt(earnKey, 0);
    }

    setState(() {
      _data = result.d;
      _loading = false;
      final watchEpisodeId = _watchToEpisodeId(widget.watchTo);
      if (watchEpisodeId != '') {
        for (var i = 0; i < _data['episodes'].length; i++) {
          if (_data['episodes'][i]['id'].toString() == watchEpisodeId) {
            _controller = PageController(initialPage: i);
            _index = i;
            break;
          }
        }
      }
      _controller ??= PageController();
    });
  }

  Widget _renderTitleBar() {
    return Positioned(
      top: 0,
      left: 0,
      height: kToolbarHeight + MediaQuery.of(context).padding.top,
      child: AnimatedOpacity(
        opacity: _ui ? 1 : 0,
        duration: Duration(milliseconds: 100),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            height: kToolbarHeight + MediaQuery.of(context).padding.top,
            width: MediaQuery.of(context).size.width,
            color: Colors.black38,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Row(
                children: [
                  Ink(
                    width: 56,
                    height: 56,
                    child: Center(child: BackButton()),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsetsGeometry.symmetric(horizontal: 16),
                      child: Text(
                        _data['info']['title'],
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '${_data['episodes'][_index]['episode']} / ${_data['episodes'].length}',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(width: 16),
                  // IconButton(
                  //   onPressed: () {
                  //     context.go('/');
                  //   },
                  //   icon: Icon(LucideIcons.house),
                  // ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _onUIChange(ui) {
    setState(() {
      _ui = ui;
    });
  }

  _onIndexChange(index) {
    _controller?.jumpToPage(index);
    setState(() {
      _index = index;
    });
  }

  _onNext() {
    if (_index < _data['episodes'].length) {
      _controller?.jumpToPage(_index + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? Loading()
          : Stack(
              fit: StackFit.expand,
              children: [
                // LazyImage(
                //   url: Global.static(_data['info']['image']),
                //   width: MediaQuery.of(context).size.width,
                //   height: MediaQuery.of(context).size.height,
                // ),
                PageView.builder(
                  controller: _controller,
                  itemCount: _data['episodes'].length,
                  scrollDirection: Axis.vertical,
                  allowImplicitScrolling: false,
                  onPageChanged: (value) {
                    setState(() {
                      _index = value;
                    });
                  },
                  itemBuilder: (context, index) {
                    return (index == _index - 1) ||
                            (index == _index + 1) ||
                            index == _index
                        ? _Video(
                            data: _data,
                            watchTo: widget.watchTo,
                            index: index,
                            onUIChange: _onUIChange,
                            onIndexChange: _onIndexChange,
                            onNext: _onNext,
                          )
                        : SizedBox();
                  },
                ),
                _renderTitleBar(),
              ],
            ),
    );
  }
}

class _Video extends StatefulWidget {
  final dynamic data;
  final dynamic watchTo;
  final int index;
  final void Function(bool) onUIChange;
  final void Function(int) onIndexChange;
  final void Function() onNext;

  const _Video({
    required this.data,
    required this.watchTo,
    required this.index,
    required this.onUIChange,
    required this.onIndexChange,
    required this.onNext,
  });

  @override
  State<StatefulWidget> createState() {
    return _VideoState();
  }
}

class _VideoState extends State<_Video> {
  String _earnKey = '';
  int _earnValue = 0;
  VideoPlayerController? _controller;
  Timer? _timer;
  BoxFit _videoFit = BoxFit.contain;
  bool _ui = true;
  bool _initialized = false;
  bool _buffering = true;
  bool _paused = false;
  int _position = 0;
  bool _favorite = false;
  bool _loading = true;
  dynamic _data;
  bool _isCompleted = false;
  bool _unlockFailed = false;
  int _earn = 0;
  bool _earnStopped = false;

  @override
  void initState() {
    super.initState();
    _videoFit = Global.sp.getBool('fullscreen') == true
        ? BoxFit.fitHeight
        : BoxFit.contain;
    _earnKey =
        'video_earn_${DateTime.now().toIso8601String().substring(0, 10)}_${FirebaseAuth.instance.currentUser?.uid}';
    _earn = Global.sp.getInt(_earnKey) ?? 0;
    _loadData();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  int _historyPosition() {
    final watchEpisodeId = _watchToEpisodeId(widget.watchTo);
    if (widget.watchTo != null &&
        watchEpisodeId != '' &&
        watchEpisodeId == _data['id'].toString()) {
      return int.tryParse('${widget.watchTo['position'] ?? 0}') ?? 0;
    }
    return 0;
  }

  _loadData() async {
    final result = await api(
      'movie/episode',
      query: {'id': widget.data['episodes'][widget.index]['id']},
    );

    if (result.c != 0) {
      return;
    }

    final earnPlayValue = await api<int>('earn/play-value');

    if (earnPlayValue.c != 0) {
      return;
    }

    _earnValue = earnPlayValue.d ?? 0;

    setState(() {
      _data = result.d;
      _loading = false;
    });

    _showUI();

    if (_data['lock']) {
      _onUnlockEpisode();
      return;
    }

    Global.logger.d(_data);

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(Global.static(_data['video'])),
      closedCaptionFile: _data['subtitle'] != ''
          ? () async {
              final response = await Global.dio.get(
                Global.static(_data['subtitle']),
              );
              return WebVTTCaptionFile(response.data);
            }()
          : null,
      videoPlayerOptions: VideoPlayerOptions(),
    );

    _controller?.initialize().then((_) {
      setState(() {
        _initialized = true;
        _position = _historyPosition();
        if (_position > 0) {
          _controller?.seekTo(Duration(seconds: _position)).then((_) {
            _controller?.play();
          });
        } else {
          _controller?.play();
        }
      });
    });

    _controller?.addListener(() async {
      if (!await WakelockPlus.enabled) {
        WakelockPlus.enable();
      }

      if (_buffering !=
          (_controller!.value.isBuffering && _controller!.value.isPlaying)) {
        setState(() {
          _buffering =
              _controller!.value.isBuffering && _controller!.value.isPlaying;
        });
      }

      if (_controller!.value.position.inSeconds != _position) {
        setState(() {
          _position = _controller!.value.position.inSeconds;
          Global.sp.setString(
            'watch_to',
            jsonEncode({
              'id': widget.data['info']['id'],
              'episode_id': int.parse(_data['id']),
              'position': _position,
              'episode': _data['episode'],
              'title': widget.data['info']['title'],
              'image': widget.data['info']['image'],
            }),
          );
          if (!_earnStopped) {
            _earn = _earn + 1;
            Global.sp.setInt(_earnKey, _earn);
            if (_earn > 0 && _earn % 60 == 0) {
              api<bool>('earn/play', method: Method.post).then((res) {
                if (res.c != 0) {
                  return;
                }
                if (res.d != true) {
                  _earnStopped = true;
                }
              });
            }
          }
        });
      }
      if (_controller!.value.isCompleted && !_isCompleted) {
        setState(() {
          _buffering = false;
        });
        widget.onNext();
        _isCompleted = true;
      }
    });
  }

  void _showUI() {
    _timer?.cancel();
    setState(() {
      _ui = true;
      widget.onUIChange(_ui);
    });
    _timer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (_initialized) {
        setState(() {
          _ui = false;
          widget.onUIChange(_ui);
        });
        timer.cancel();
      }
    });
  }

  _onUnlockEpisode() async {
    if (Platform.isAndroid) {
      return;
    }
    final close = Global.loading();
    var result = await api(
      'movie/episode/will-unlock',
      query: {'id': _data['id']},
    );
    if (result.c != 0) {
      setState(() {
        _unlockFailed = true;
      });
      close();
      return;
    }
    await rewardedAd((watched) async {
      if (!watched) {
        setState(() {
          _unlockFailed = true;
        });
        close();
        return;
      }
      result = await api(
        'movie/episode/do-unlock',
        method: Method.post,
        data: {'id': _data['id'], 'cipher': result.d},
      );
      if (result.c != 0) {
        setState(() {
          _unlockFailed = true;
        });
        close();
        return;
      }
      close();
      await _loadData();
    });
  }

  Widget _renderUnlock() {
    return Center(
      child: InkWell(
        onTap: () async {
          await context.push('/membership');
          if (mounted && context.read<UserState>().isVip) {
            setState(() {
              _loading = true;
              _loadData();
            });
          }
        },
        child: Ink(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.orange, Colors.red]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Icon(TablerIcons.lock_open, size: 20),
              Text(t.unlock_now, style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _renderController() {
    return _data['lock']
        ? (_unlockFailed
              ? Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _onUnlockEpisode,
                    child: Ink(
                      height: 48,
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber, Colors.red],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          Icon(LucideIcons.lockOpen, size: 18),
                          Text(
                            t.unlock_now_ad,
                            style: TextStyle(height: -0.1, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : SizedBox())
        : Positioned.fill(
            child: _buffering && !_paused
                ? Center(
                    child: LoadingAnimationWidget.threeArchedCircle(
                      color: Colors.white,
                      size: 32,
                    ),
                  )
                : Center(
                    child: Material(
                      type: MaterialType.transparency,
                      child: AnimatedOpacity(
                        opacity: _ui ? 1 : 0,
                        duration: Duration(milliseconds: 100),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(36),
                          onTap: () {
                            if (!_uiIsShow()) {
                              return;
                            }
                            if (_paused) {
                              _controller?.play();
                              setState(() {
                                _paused = false;
                              });
                            } else {
                              WakelockPlus.disable();
                              _controller?.pause();
                              setState(() {
                                _paused = true;
                              });
                            }
                          },
                          child: Ink(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(36),
                            ),
                            child: Icon(
                              _paused ? LucideIcons.play : LucideIcons.pause,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          );
  }

  _renderButton() {
    return Positioned(
      bottom: 128,
      right: 16,
      child: AnimatedOpacity(
        opacity: _ui ? 1 : 0,
        duration: Duration(milliseconds: 100),
        child: Column(
          spacing: 24,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: () {
                if (!_uiIsShow()) {
                  return;
                }
                api(
                  'movie/favorite',
                  method: Method.post,
                  data: {'id': widget.data['info']['id'], 'time': _position},
                );
                Global.sp.setBool('update_favorite', true);
                setState(() {
                  _favorite = !_favorite;
                });
              },
              child: Column(
                spacing: 4,
                children: [
                  Icon(
                    TablerIcons.star_filled,
                    size: 36,
                    color: _favorite ? Colors.amberAccent : null,
                  ),
                  Text(
                    '${widget.data['info']['favorite']}K',
                    style: TextStyle(fontSize: 12, height: 1),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                if (!_uiIsShow()) {
                  return;
                }
                _showList();
              },
              child: Column(
                spacing: 4,
                children: [
                  Icon(TablerIcons.layout_grid_filled, size: 36),
                  Text(
                    t.episode_list,
                    style: TextStyle(fontSize: 12, height: 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _renderProgress() {
    return Positioned(
      bottom: 48,
      child: AnimatedOpacity(
        opacity: _ui ? 1 : 0,
        duration: Duration(milliseconds: 100),
        child: GestureDetector(
          onTap: () {
            _showUI();
          },
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            height: 40,
            padding: EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: _ui,
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    colors: VideoProgressColors(
                      playedColor: Colors.white70,
                      bufferedColor: Colors.white60,
                      backgroundColor: Colors.white30,
                    ),
                  ),
                ),
                Text(
                  '${(_position / 60).floor().toString().padLeft(2, '0')}:${(_position % 60).toString().padLeft(2, '0')}/${_controller!.value.duration.inMinutes.toString().padLeft(2, '0')}:${(_controller!.value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderEarn() {
    return Positioned(
      left: 0,
      top: kToolbarHeight + MediaQuery.of(context).padding.top,
      child: AnimatedOpacity(
        opacity: _ui ? 1 : 0,
        duration: Duration(milliseconds: 100),
        child: InkWell(
          onTap: () {
            Global.info(
              t.earn.earn_amount(amount: (_earn / 60).floor() * _earnValue),
              icon: Icon(
                TablerIcons.coins,
                size: 32,
                color: Colors.amber.shade300,
              ),
            );
          },
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        left: 0,
                        child: Center(
                          child: Text(
                            (60 - _earn % 60).toString(),
                            style: TextStyle(fontSize: 12, height: 1),
                          ),
                        ),
                      ),
                      CircularProgressIndicator(
                        value: (_earn % 60) / 60,
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                      CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 2.5,
                        color: Colors.white24,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Icon(TablerIcons.coins, size: 16),
                SizedBox(width: 4),
                AnimatedFlipCounter(
                  value: (_earn / 60).floor() * _earnValue,
                  suffix: ' ${t.earn.rewarded}',
                  textStyle: TextStyle(
                    fontSize: 16,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderFullscreen() {
    return Positioned(
      top: kToolbarHeight + MediaQuery.of(context).padding.top,
      right: 0,
      child: AnimatedOpacity(
        opacity: _ui ? 1 : 0,
        duration: Duration(milliseconds: 100),
        child: InkWell(
          onTap: () {
            if (!_uiIsShow()) {
              return;
            }
            setState(() {
              _videoFit = _videoFit == BoxFit.fitHeight
                  ? BoxFit.contain
                  : BoxFit.fitHeight;
              Global.sp.setBool('fullscreen', _videoFit == BoxFit.fitHeight);
            });
          },
          child: Ink(
            width: 64,
            height: 64,
            child: Icon(
              _videoFit == BoxFit.fitHeight
                  ? TablerIcons.minimize
                  : TablerIcons.maximize,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  void _showList() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 24, right: 8, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                spacing: 8,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          widget.data['info']['title'],
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  CloseButton(),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 24, right: 24, bottom: 16),
              child: Text(
                '${t.episode} ${widget.data['episodes'][widget.index]['episode']} / ${widget.data['episodes'].length}',
                style: TextStyle(
                  color: Theme.of(context).disabledColor,
                  fontSize: 14,
                ),
              ),
            ),
            Divider(height: 1),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  top: 16,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: GridView.builder(
                    itemCount: widget.data['episodes'].length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      return InkWell(
                        onTap: () {
                          if (index != widget.index) {
                            widget.onIndexChange(index);
                            context.pop();
                          }
                        },
                        child: Stack(
                          children: [
                            Ink(
                              decoration: BoxDecoration(
                                color: index == widget.index
                                    ? Colors.red
                                    : const Color.fromARGB(
                                        255,
                                        117,
                                        122,
                                        143,
                                      ).withAlpha(50),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  (index + 1).toString(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            if (widget.data['episodes'][index]['vip'] != 0 &&
                                widget.data['episodes'][index]['locked'] == 1 &&
                                !context.read<UserState>().isVip)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(TablerIcons.lock, size: 12),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _uiIsShow() {
    final uiState = _ui;
    _showUI();
    if (!uiState) {
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? Loading()
        : Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (_initialized)
                FittedBox(
                  fit: _videoFit,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              if (_initialized)
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.6,
                  left: 32,
                  right: 32,
                  child: Text(
                    _controller!.value.caption.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 8,
                          offset: Offset.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              InkWell(
                onTap: () {
                  if (_ui) {
                    _timer?.cancel();
                    setState(() {
                      _ui = false;
                      widget.onUIChange(_ui);
                    });
                  } else {
                    _showUI();
                  }
                },
              ),
              _renderController(),
              _renderButton(),
              if (_initialized) _renderProgress(),
              if (_initialized) _renderFullscreen(),
              if (_initialized) _renderEarn(),
              if (!_loading && _data['lock']) _renderUnlock(),
            ],
          );
  }
}
