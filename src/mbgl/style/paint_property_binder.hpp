#pragma once

#include <mbgl/programs/attributes.hpp>
#include <mbgl/gl/attribute.hpp>
#include <mbgl/gl/uniform.hpp>
#include <mbgl/util/type_list.hpp>
#include "paint_property_statistics.hpp"

namespace mbgl {
namespace style {

/*
   ZoomInterpolatedAttribute<Attr> is a 'compound' attribute, representing two values of the
   the base attribute Attr.  These two values are provided to the shader to allow interpolation
   between zoom levels, without the need to repopulate vertex buffers each frame as the map is
   being zoomed.
*/
template <class A>
using ZoomInterpolatedAttributeType = gl::Attribute<typename A::ValueType, A::Dimensions * 2>;

inline std::array<float, 1> attributeValue(float v) {
    return {{ v }};
}

/*
    Encode a four-component color value into a pair of floats.  Since csscolorparser
    uses 8-bit precision for each color component, for each float we use the upper 8
    bits for one component (e.g. (color.r * 255) * 256), and the lower 8 for another.
    
    Also note:
     - Colors come in as floats 0..1, so we scale by 255.
     - Casting the scaled values to ints is important: without doing this, e.g., the
       fractional part of the `r` component would corrupt the lower-8 bits of the encoded
       value, which must be reserved for the `g` component.
*/
inline std::array<float, 2> attributeValue(const Color& color) {
    return {{
        static_cast<float>(static_cast<uint16_t>(color.r * 255) * 256 + static_cast<uint16_t>(color.g * 255)),
        static_cast<float>(static_cast<uint16_t>(color.b * 255) * 256 + static_cast<uint16_t>(color.a * 255))
    }};
}

template <size_t N>
std::array<float, N*2> zoomInterpolatedAttributeValue(const std::array<float, N>& min, const std::array<float, N>& max) {
    std::array<float, N*2> result;
    for (size_t i = 0; i < N; i++) {
        result[i]   = min[i];
        result[i+N] = max[i];
    }
    return result;
}

/*
   PaintPropertyBinder is an abstract class serving as the interface definition for
   the strategy used for constructing, uploading, and binding paint property data as
   GLSL attributes.

   It has three concrete subclasses, one for each of the three strategies we use:

   * For _constant_ properties -- those whose value is a constant, or the constant
     result of evaluating a camera function at a particular camera position -- we
     don't need a vertex buffer, and can instead use a constant attribute binding
     via the `glVertexAttrib*` family of functions.
   * For source functions, we use a vertex buffer with a single attribute value,
     the evaluated result of the source function for the given feature.
   * For composite functions, we use a vertex buffer with two attributes: min and
     max values covering the range of zooms at which we expect the tile to be
     displayed. These values are calculated by evaluating the composite function for
     the given feature at strategically chosen zoom levels. In addition to this
     attribute data, we also use a uniform value which the shader uses to interpolate
     between the min and max value at the final displayed zoom level. The use of a
     uniform allows us to cheaply update the value on every frame.

   Note that the shader source is the same regardless of the strategy used to bind
   the attribute -- in all cases the attribute is declared as a vec2, in order to
   support composite min and max values (color attributes use a vec4 with special
   packing). When the constant or source function strategies are used, the
   interpolation uniform value is set to zero, and the second attribute element is
   unused. This differs from the GL JS implementation, which dynamically generates
   shader source based on the strategy used. We found that in WebGL, using
   `glVertexAttrib*` was unnacceptably slow. Additionally, in GL Native we have
   implemented binary shader caching, which works better if the shaders are constant.
*/
template <class P, class T, class A, class Statistics>
class PaintPropertyBinder {
public:
    using Attribute = ZoomInterpolatedAttributeType<A>;
    using AttributeBinding = typename Attribute::Binding;

    virtual ~PaintPropertyBinder() = default;

    virtual void populateVertexVector(const GeometryTileFeature& feature, std::size_t length, Statistics& statistics) = 0;
    virtual void upload(gl::Context& context) = 0;
    virtual AttributeBinding attributeBinding(const PossiblyEvaluatedPropertyValue<T>& currentValue) const = 0;
    virtual float interpolationFactor(float currentZoom) const = 0;

    static std::unique_ptr<PaintPropertyBinder> create(const PossiblyEvaluatedPropertyValue<T>& value, float zoom, T defaultValue);
};

template <class P, class T, class A, class Statistics>
class ConstantPaintPropertyBinder : public PaintPropertyBinder<P, T, A, Statistics> {
public:
    using Attribute = ZoomInterpolatedAttributeType<A>;
    using AttributeBinding = typename Attribute::Binding;

    ConstantPaintPropertyBinder(T constant_)
        : constant(std::move(constant_)) {
    }

    void populateVertexVector(const GeometryTileFeature&, std::size_t, Statistics&) override {}

    void upload(gl::Context&) override {}

    AttributeBinding attributeBinding(const PossiblyEvaluatedPropertyValue<T>& currentValue) const override {
        auto value = attributeValue(currentValue.constantOr(constant));
        return typename Attribute::ConstantBinding {
            zoomInterpolatedAttributeValue(value, value)
        };
    }

    float interpolationFactor(float) const override {
        return 0.0f;
    }

private:
    T constant;
};

template <class P, class T, class A, class Statistics>
class SourceFunctionPaintPropertyBinder : public PaintPropertyBinder<P, T, A, Statistics> {
public:
    using BaseAttribute = A;
    using BaseAttributeValue = typename BaseAttribute::Value;
    using BaseVertex = gl::detail::Vertex<BaseAttribute>;

    using Attribute = ZoomInterpolatedAttributeType<A>;
    using AttributeBinding = typename Attribute::Binding;

    SourceFunctionPaintPropertyBinder(SourceFunction<T> function_, T defaultValue_)
        : function(std::move(function_)),
          defaultValue(std::move(defaultValue_)) {
    }

    void populateVertexVector(const GeometryTileFeature& feature, std::size_t length, Statistics& statistics) override {
        auto evaluated = function.evaluate(feature, defaultValue);
        statistics.template add<P>(evaluated);
        auto value = attributeValue(evaluated);
        for (std::size_t i = vertexVector.vertexSize(); i < length; ++i) {
            vertexVector.emplace_back(BaseVertex { value });
        }
    }

    void upload(gl::Context& context) override {
        vertexBuffer = context.createVertexBuffer(std::move(vertexVector));
    }

    AttributeBinding attributeBinding(const PossiblyEvaluatedPropertyValue<T>& currentValue) const override {
        if (currentValue.isConstant()) {
            BaseAttributeValue value = attributeValue(*currentValue.constant());
            return typename Attribute::ConstantBinding {
                zoomInterpolatedAttributeValue(value, value)
            };
        } else {
            return Attribute::variableBinding(*vertexBuffer, 0, BaseAttribute::Dimensions);
        }
    }

    float interpolationFactor(float) const override {
        return 0.0f;
    }

private:
    SourceFunction<T> function;
    T defaultValue;
    gl::VertexVector<BaseVertex> vertexVector;
    optional<gl::VertexBuffer<BaseVertex>> vertexBuffer;
};

template <class P, class T, class A, class Statistics>
class CompositeFunctionPaintPropertyBinder : public PaintPropertyBinder<P, T, A, Statistics> {
public:
    using BaseAttribute = A;
    using BaseAttributeValue = typename BaseAttribute::Value;

    using Attribute = ZoomInterpolatedAttributeType<A>;
    using AttributeValue = typename Attribute::Value;
    using AttributeBinding = typename Attribute::Binding;
    using Vertex = gl::detail::Vertex<Attribute>;

    CompositeFunctionPaintPropertyBinder(CompositeFunction<T> function_, float zoom, T defaultValue_)
        : function(std::move(function_)),
          defaultValue(std::move(defaultValue_)),
          coveringRanges(function.coveringRanges(zoom)) {
    }

    void populateVertexVector(const GeometryTileFeature& feature, std::size_t length, Statistics& statistics) override {
        Range<T> range = function.evaluate(std::get<1>(coveringRanges), feature, defaultValue);
        statistics.template add<P>(range);
        AttributeValue value = zoomInterpolatedAttributeValue(
            attributeValue(range.min),
            attributeValue(range.max));
        for (std::size_t i = vertexVector.vertexSize(); i < length; ++i) {
            vertexVector.emplace_back(Vertex { value });
        }
    }

    void upload(gl::Context& context) override {
        vertexBuffer = context.createVertexBuffer(std::move(vertexVector));
    }

    AttributeBinding attributeBinding(const PossiblyEvaluatedPropertyValue<T>& currentValue) const override {
        if (currentValue.isConstant()) {
            BaseAttributeValue value = attributeValue(*currentValue.constant());
            return typename Attribute::ConstantBinding {
                zoomInterpolatedAttributeValue(value, value)
            };
        } else {
            return Attribute::variableBinding(*vertexBuffer, 0);
        }
    }

    float interpolationFactor(float currentZoom) const override {
        return util::interpolationFactor(1.0f, std::get<0>(coveringRanges), currentZoom);
    }

private:
    using InnerStops = typename CompositeFunction<T>::InnerStops;
    CompositeFunction<T> function;
    T defaultValue;
    std::tuple<Range<float>, Range<InnerStops>> coveringRanges;
    gl::VertexVector<Vertex> vertexVector;
    optional<gl::VertexBuffer<Vertex>> vertexBuffer;
};

template <class P, class T, class A, class Statistics>
std::unique_ptr<PaintPropertyBinder<P, T, A, Statistics>>
PaintPropertyBinder<P, T, A, Statistics>::create(const PossiblyEvaluatedPropertyValue<T>& value, float zoom, T defaultValue) {
    return value.match(
        [&] (const T& constant) -> std::unique_ptr<PaintPropertyBinder<P, T, A, Statistics>> {
            return std::make_unique<ConstantPaintPropertyBinder<P, T, A, Statistics>>(constant);
        },
        [&] (const SourceFunction<T>& function) {
            return std::make_unique<SourceFunctionPaintPropertyBinder<P, T, A, Statistics>>(function, defaultValue);
        },
        [&] (const CompositeFunction<T>& function) {
            return std::make_unique<CompositeFunctionPaintPropertyBinder<P, T, A, Statistics>>(function, zoom, defaultValue);
        }
    );
}

template <class Attr>
struct ZoomInterpolatedAttribute {
    static auto name() { return Attr::name(); }
    using Type = ZoomInterpolatedAttributeType<typename Attr::Type>;
};

template <class Attr>
struct InterpolationUniform : gl::UniformScalar<InterpolationUniform<Attr>, float> {
    static auto name() {
        static const std::string name = Attr::name() + std::string("_t");
        return name.c_str();
    }
};

template <class Ps>
class PaintPropertyBinders;

template <class... Ps>
class PaintPropertyBinders<TypeList<Ps...>> {
public:
    using Statistics = PaintPropertyStatistics<Ps...>;

    template <class P>
    using Binder = PaintPropertyBinder<P, typename P::Type, typename P::Attribute::Type, Statistics>;

    using Binders = IndexedTuple<
        TypeList<Ps...>,
        TypeList<std::unique_ptr<Binder<Ps>>...>>;

    template <class EvaluatedProperties>
    PaintPropertyBinders(const EvaluatedProperties& properties, float z)
        : binders(Binder<Ps>::create(properties.template get<Ps>(), z, Ps::defaultValue())...) {
        (void)z; // Workaround for https://gcc.gnu.org/bugzilla/show_bug.cgi?id=56958
    }

    PaintPropertyBinders(PaintPropertyBinders&&) = default;
    PaintPropertyBinders(const PaintPropertyBinders&) = delete;

    void populateVertexVectors(const GeometryTileFeature& feature, std::size_t length) {
        util::ignore({
            (binders.template get<Ps>()->populateVertexVector(feature, length, statistics), 0)...
        });
    }

    void upload(gl::Context& context) {
        util::ignore({
            (binders.template get<Ps>()->upload(context), 0)...
        });
    }

    template <class P>
    using Attribute = ZoomInterpolatedAttribute<typename P::Attribute>;

    using Attributes = gl::Attributes<Attribute<Ps>...>;
    using AttributeBindings = typename Attributes::Bindings;

    template <class EvaluatedProperties>
    AttributeBindings attributeBindings(const EvaluatedProperties& currentProperties) const {
        return AttributeBindings {
            binders.template get<Ps>()->attributeBinding(currentProperties.template get<Ps>())...
        };
    }

    using Uniforms = gl::Uniforms<InterpolationUniform<typename Ps::Attribute>...>;
    using UniformValues = typename Uniforms::Values;

    UniformValues uniformValues(float currentZoom) const {
        (void)currentZoom; // Workaround for https://gcc.gnu.org/bugzilla/show_bug.cgi?id=56958
        return UniformValues {
            typename InterpolationUniform<typename Ps::Attribute>::Value {
                binders.template get<Ps>()->interpolationFactor(currentZoom)
            }...
        };
    }

    Statistics statistics;

private:
    Binders binders;
};

} // namespace style
} // namespace mbgl
