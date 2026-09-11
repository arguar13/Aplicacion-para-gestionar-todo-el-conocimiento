import 'package:cristo_es_el_salvador/core/domain/entities/user.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'dashboard_state.freezed.dart';

@freezed
sealed class DashboardState with _$DashboardState {
  const factory DashboardState.initial() = DashboardInitial;
  const factory DashboardState.loading() = DashboardLoading;
  const factory DashboardState.loaded(User user) = DashboardLoaded;
  const factory DashboardState.error(String message) = DashboardError;
}
