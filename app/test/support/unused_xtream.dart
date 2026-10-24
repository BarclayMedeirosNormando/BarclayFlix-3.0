import 'package:barclayflix/core/network/api_result.dart';
import 'package:barclayflix/features/xtream/data/xtream_models.dart';

/// Implementações vazias dos métodos de catálogo, para fakes que não os usam.
mixin UnusedXtreamMethods {
  Future<ApiResult<List<XtreamMovie>>> vodStreams(
    XtreamSession session,
    String categoryId,
  ) async =>
      const ApiSuccess<List<XtreamMovie>>([]);

  Future<ApiResult<List<XtreamSeries>>> seriesList(
    XtreamSession session,
    String categoryId,
  ) async =>
      const ApiSuccess<List<XtreamSeries>>([]);

  Future<ApiResult<XtreamSeriesDetail>> seriesInfo(
    XtreamSession session,
    String seriesId,
  ) async =>
      const ApiError<XtreamSeriesDetail>('NOT_USED', 'não usado neste teste');

  Future<ApiResult<XtreamVodInfo>> vodInfo(
    XtreamSession session,
    String vodId,
  ) async =>
      const ApiError<XtreamVodInfo>('NOT_USED', 'não usado neste teste');
}
