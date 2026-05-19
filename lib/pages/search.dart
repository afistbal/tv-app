import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:yogotv/api.dart';
import 'package:yogotv/components/loading.dart';
import 'package:yogotv/i18n/strings.g.dart';
import 'package:yogotv/widgets/film_item.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Search();
  }
}

class _Search extends State<Search> {
  final _focusNode = FocusNode();
  List<dynamic> _list = [];
  bool _loading = false;
  bool _noContent = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 48) / 2;
    final height = width / 3 * 4;

    return Scaffold(
      appBar: AppBar(title: Text(t.search)),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              onSubmitted: (value) async {
                setState(() {
                  _loading = true;
                });
                final result = await api(
                  'movie',
                  query: {'keyword': value.trim()},
                );

                setState(() {
                  _list = result.d['data'];
                  _noContent = result.d['data'].length == 0;
                  _loading = false;
                });
              },
              focusNode: _focusNode,
              keyboardType: TextInputType.text,
              maxLength: 32,
              autofocus: true,
              onTapOutside: (_) {
                FocusManager.instance.primaryFocus?.unfocus();
              },
              decoration: InputDecoration(
                hintText: t.search_placeholder,
                counterText: '',
                suffixIcon: Icon(LucideIcons.search, color: Colors.white54),
              ),
            ),
          ),
          _loading || _noContent
              ? Padding(
                  padding: EdgeInsets.all(16),
                  child: _noContent
                      ? Center(
                          child: Text(
                            t.no_search_result,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : Loading(),
                )
              : Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.only(
                      top: 16,
                      left: 16,
                      bottom: 32,
                      right: 16,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      mainAxisExtent: height + 52,
                    ),
                    itemCount: _list.length,
                    itemBuilder: (context, index) {
                      return FilmItem(
                        id: _list[index]['id'],
                        width: width,
                        height: height,
                        image: _list[index]['image'],
                        title: _list[index]['title'],
                        recommend: false,
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
