import ArgenticCore
import SwiftUI

struct InspectorView: View {
    @Bindable var model: FractalModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $model.inspectorTab) {
                ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            switch model.inspectorTab {
            case .color: ColorPanel(model: model)
            case .fractal: FractalPanel(model: model)
            case .size: SizePanel(model: model)
            }
        }
    }
}

// MARK: Colour

private struct ChannelSliders: View {
    let title: String
    @Binding var values: [Double]
    let range: ClosedRange<Double>
    var step = 1.0
    var onChange: () -> Void

    private let names = ["Red", "Green", "Blue"]

    var body: some View {
        Section(title) {
            ForEach(0..<3, id: \.self) { i in
                HStack {
                    Text(names[i]).frame(width: 44, alignment: .leading)
                    Slider(value: binding(i), in: range, step: step)
                    Text(values[i], format: .number.precision(.fractionLength(step < 1 ? 2 : 0)))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private func binding(_ i: Int) -> Binding<Double> {
        Binding(get: { values[i] }, set: { values[i] = $0; onChange() })
    }
}

private struct ColorPanel: View {
    @Bindable var model: FractalModel

    var body: some View {
        Form {
            Section("Mixing") {
                Picker("Blend", selection: Binding(get: { model.parameters.blend }, set: { model.chooseBlend($0) })) {
                    ForEach(1...Catalog.blendGroups.last!.range.upperBound, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                Picker("RGB order", selection: Binding(get: { model.parameters.rgbOrder }, set: { model.chooseRGBOrder($0) })) {
                    ForEach(Array(Catalog.rgbOrders.enumerated()), id: \.offset) { Text($1).tag($0 + 1) }
                }
                HStack {
                    Text("Render")
                    Slider(value: $model.parameters.renderScale, in: 0...8)
                    Text(model.parameters.renderScale, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            ChannelSliders(title: "Steps", values: $model.parameters.colors.step, range: 0...255) { model.recolor() }
            ChannelSliders(title: "Start", values: $model.parameters.colors.start, range: 0...255) { model.recolor() }
            ChannelSliders(title: "Saturation", values: $model.parameters.colors.saturation, range: 0...4, step: 0.01) { model.recolor() }
            ChannelSliders(title: "Offset", values: $model.parameters.colors.offset, range: -255...255) { model.recolor() }
            Button("Reset Colours") {
                model.parameters.colors = ColorControls()
                model.parameters.renderScale = 1
                model.recolor()
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.parameters.renderScale) { model.recolor() }
    }
}

// MARK: Fractal

private struct FractalPanel: View {
    @Bindable var model: FractalModel

    var body: some View {
        Form {
            Section("Iteration") {
                LabeledContent("Max iterations") {
                    TextField("", value: $model.parameters.maxIterations, format: .number)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Stalks & bubbles radius") {
                    TextField("", value: $model.parameters.trapRadius, format: .number)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Scale factor") {
                    TextField("", value: $model.parameters.scaleFactor, format: .number)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("Lyapunov (renders 30-32)") {
                Toggle("Enable Lyapunov", isOn: Binding(
                    get: { model.isLyapunovEnabled },
                    set: { model.setLyapunovEnabled($0) }
                ))
                Picker("Map", selection: Binding(
                    get: { model.selectedLyapunovMap },
                    set: { model.chooseLyapunovMap($0) }
                )) {
                    ForEach(Catalog.lyapunovMaps) { Text("\($0.id).) \($0.title)").tag($0.id) }
                }
                .disabled(!model.isLyapunovEnabled)
                Picker("Derivative", selection: $model.parameters.lyapunovDerivative) {
                    ForEach(Catalog.lyapunovDerivatives) { Text("\($0.id).) \($0.title)").tag($0.id) }
                }
                .disabled(!model.isLyapunovEnabled)
                Picker("Mapping", selection: $model.parameters.lyapunovMapping) {
                    ForEach(Catalog.lyapunovMappings) { Text("\($0.id).) \($0.title)").tag($0.id) }
                }
                .disabled(!model.isLyapunovEnabled)
                Button("Clear Lyapunov Settings") { model.clearLyapunovSettings() }
                    .disabled(!model.isLyapunovEnabled)
            }
            Section("Julia") {
                Toggle("Julia mode", isOn: $model.parameters.juliaMode)
                LabeledContent("Julia X") {
                    TextField("", value: $model.parameters.juliaX, format: .number)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Julia Y") {
                    TextField("", value: $model.parameters.juliaY, format: .number)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Inside out", isOn: $model.parameters.insideOut)
                Picker("Coordinates", selection: Binding(
                    get: { model.parameters.coordinateFlag },
                    set: { model.setCoordinateFlag($0) }
                )) {
                    Text("Normal").tag(0)
                    Text("Rotate90 (swap x and y)").tag(1)
                    Text("Rotate90Mirror").tag(2)
                    Text("Mirror").tag(3)
                }
            }
            Section("View") {
                LabeledContent("X min") { viewportField($model.parameters.viewport.xMin) }
                LabeledContent("X max") { viewportField($model.parameters.viewport.xMax) }
                LabeledContent("Y min") { viewportField($model.parameters.viewport.yMin) }
                LabeledContent("Y max") { viewportField($model.parameters.viewport.yMax) }
            }
            Button("Apply") { model.draw() }
                .keyboardShortcut(.return, modifiers: .command)
        }
        .formStyle(.grouped)
    }

    private func viewportField(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number.precision(.significantDigits(1...15)))
            .multilineTextAlignment(.trailing)
    }
}

// MARK: Size

private struct SizePanel: View {
    @Bindable var model: FractalModel

    var body: some View {
        Form {
            Section("Presets") {
                ForEach(Array(Catalog.sizePresets.enumerated()), id: \.offset) { _, size in
                    Button("\(size.width) by \(size.height)") {
                        model.parameters.width = size.width
                        model.parameters.height = size.height
                    }
                }
            }
            Section("Size") {
                LabeledContent("Width") {
                    TextField("", value: $model.parameters.width, format: .number).multilineTextAlignment(.trailing)
                }
                LabeledContent("Height") {
                    TextField("", value: $model.parameters.height, format: .number).multilineTextAlignment(.trailing)
                }
                Picker("Anti-alias", selection: $model.parameters.antiAlias) {
                    Text("Off").tag(1)
                    Text("2:1").tag(2)
                    Text("3:1").tag(3)
                    Text("4:1").tag(4)
                }
            }
            Button("Apply") { model.setSize(width: model.parameters.width, height: model.parameters.height) }
        }
        .formStyle(.grouped)
    }
}
