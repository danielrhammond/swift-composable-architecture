import ComposableArchitecture
import SwiftUI

private let readMe = """
  This screen demonstrates navigation that depends on loading optional state from a list element.

  Tapping a row simultaneously navigates to a screen that depends on its associated counter state \
  and fires off an effect that will load this state a second later.
  """

struct NavigateAndLoadListState: Equatable {
  var rows: IdentifiedArrayOf<Row> = [
    Row(count: 1, id: UUID()),
    Row(count: 42, id: UUID()),
    Row(count: 100, id: UUID()),
  ]
  var selection: Identified<Row.ID, CounterState?>?

  struct Row: Equatable, Identifiable {
    var count: Int
    let id: UUID
  }
}

enum NavigateAndLoadListAction: Equatable {
  case counter(CounterAction)
  case setNavigation(selection: UUID?)
  case setNavigationSelectionDelayCompleted
}

struct NavigateAndLoadListEnvironment {
  var mainQueue: AnySchedulerOf<DispatchQueue>
}

let navigateAndLoadListReducer =
  counterReducer
  .optional()
  .pullback(state: \Identified.value, action: .self, environment: { $0 })
  .optional()
  .pullback(
    state: \NavigateAndLoadListState.selection,
    action: /NavigateAndLoadListAction.counter,
    environment: { _ in CounterEnvironment() }
  )
  .combined(
    with: Reducer<
      NavigateAndLoadListState, NavigateAndLoadListAction, NavigateAndLoadListEnvironment
    > { state, action, environment in

      enum CancelID {}

      switch action {
      case .counter:
        return .none

      case let .setNavigation(selection: .some(id)):
        state.selection = Identified(nil, id: id)
        return .task {
          try await environment.mainQueue.sleep(for: 1)
          return .setNavigationSelectionDelayCompleted
        }
        .cancellable(id: CancelID.self, cancelInFlight: true)

      case .setNavigation(selection: .none):
        if let selection = state.selection, let count = selection.value?.count {
          state.rows[id: selection.id]?.count = count
        }
        state.selection = nil
        return .cancel(id: CancelID.self)

      case .setNavigationSelectionDelayCompleted:
        guard let id = state.selection?.id else { return .none }
        state.selection?.value = CounterState(count: state.rows[id: id]?.count ?? 0)
        return .none
      }
    }
  )

struct NavigateAndLoadListView: View {
  let store: Store<NavigateAndLoadListState, NavigateAndLoadListAction>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Form {
        Section {
          AboutView(readMe: readMe)
        }
        ForEach(viewStore.rows) { row in
          NavigationLink(
            destination: IfLetStore(
              self.store.scope(
                state: \.selection?.value,
                action: NavigateAndLoadListAction.counter
              )
            ) {
              CounterView(store: $0)
            } else: {
              ProgressView()
            },
            tag: row.id,
            selection: viewStore.binding(
              get: \.selection?.id,
              send: NavigateAndLoadListAction.setNavigation(selection:)
            )
          ) {
            Text("Load optional counter that starts from \(row.count)")
          }
        }
      }
    }
    .navigationTitle("Navigate and load")
  }
}

struct NavigateAndLoadListView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationView {
      NavigateAndLoadListView(
        store: Store(
          initialState: NavigateAndLoadListState(
            rows: [
              NavigateAndLoadListState.Row(count: 1, id: UUID()),
              NavigateAndLoadListState.Row(count: 42, id: UUID()),
              NavigateAndLoadListState.Row(count: 100, id: UUID()),
            ]
          ),
          reducer: navigateAndLoadListReducer,
          environment: NavigateAndLoadListEnvironment(
            mainQueue: .main
          )
        )
      )
    }
    .navigationViewStyle(.stack)
  }
}
