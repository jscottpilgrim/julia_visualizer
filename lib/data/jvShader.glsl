//jscottpilgrim
//J.P.Scott 2019

//10 color julia distance estimator

//reference: http://www.iquilezles.org/www/articles/distancefractals/distancefractals.htm

//fragment shader

#ifdef GL_ES
precision highp float;
precision mediump int;
#endif

uniform vec2 resolution;

uniform vec2 center;
uniform float zoom;

uniform vec2 juliaParam;
uniform int exponent;

uniform int maxIterations;
uniform float escapeRadius;

//handle freq mag modifier and cycle offset in cpu. pass final colors to shader to calc with distance estimate

uniform vec3 color0;
uniform vec3 color1;
uniform vec3 color2;
uniform vec3 color3;
uniform vec3 color4;
uniform vec3 color5;
uniform vec3 color6;
uniform vec3 color7;
uniform vec3 color8;
uniform vec3 color9;

const int numColors = 10;

vec2 complexSquare( vec2 v )
{
	return vec2(
		v.x * v.x - v.y * v.y,
		v.x * v.y * 2.0
	);
}

vec2 complexCube( vec2 v )
{
	return vec2(
		( v.x * v.x * v.x ) - ( 3.0 * v.x * v.y * v.y ),
		( 3.0 * v.x * v.x * v.y ) - ( v.y * v.y * v.y )
	);
}

vec2 complexMultiply( vec2 a, vec2 b )
{
	return vec2(
		( a.x * b.x - a.y * b.y ),
		( a.x * b.y + a.y * b.x )
	);
}


float distanceEstimate( vec2 uv )
{
	bool escape = false;
	vec2 c = juliaParam;
	vec2 z = uv * zoom + center;
	vec2 dz = vec2( 1.0, 0.0 );

	for ( int i = 0 ; i < maxIterations; i++ ) {
		//z' = 2 * z * z'
		//dz = 2.0 * vec2( z.x * dz.x - z.y * dz.y, z.x * dz.y + z.y * dz.x );

		vec2 n = z;
		int countdown = exponent - 2;
		while( countdown > 0 )
		{
			n = complexMultiply( z, n );
			countdown--;
		}
		dz = float( exponent ) * complexMultiply( n, dz );

		//mandelbrot function on z
		if( exponent == 2)
			{ z = c + complexSquare( z ); }
		else if( exponent == 3 )
			{ z = c + complexCube( z ); }
		else
		{
			//n = z;
			//countdown = exponent - 1;
			//while( countdown > 0)
			//{
			//	n = complexMultiply( z, n );
			//	countdown--;
			//}
			n = complexMultiply( z, n );
			z = c + n;
		}

		//higher escape radius for detail
		if ( dot( z, z ) > escapeRadius )
		{
			escape = true;
			break;
		}
	}

	float d = 0.01;

	if ( escape )
	{
		//distance
		//d(c) = (|z|*log|z|)/|z'|

		//idk why inigo uses this formula. optimization of distance estimation?
		//float d = 0.5*sqrt(dot(z,z)/dot(dz,dz))*log(dot(z,z));

		d = sqrt( dot( z, z ) );
		d *= log( sqrt( dot( z, z ) ) );
		d /= sqrt( dot( dz, dz ) );

		d = clamp( pow( 4.0 * d, 0.1 ), 0.01, 1.0 );
	}

	return ( ( 1.0 - d ) );
}

vec3 preFractalColor( vec2 uv )
{
	//initialize return val
	vec3 color = vec3( 0.0 );
	//make array of color uniforms
	vec3 colors[10] = vec3[]( color0.xyz, color1.xyz, color2.xyz, color3.xyz, color4.xyz, color5.xyz, color6.xyz, color7.xyz, color8.xyz, color9.xyz );

	//get distance from center
	float d = sqrt( ( uv.x * uv.x ) + ( uv.y * uv.y ) );

	//float maxRadius = max( resolution.x, resolution.y ) * 0.5;
	float maxRadius = min( resolution.x, resolution.y ) * 0.5;
	float step = maxRadius / 10.0;

	float di = 1.0;
	for ( int i = 0; i < numColors; i++ )
	{
		float zRadius = step * (di - 0.5);
		//shortest distance from point to circle: abs( sqrt( ( x - h ) ^ 2 + ( y - k ) ^ 2 )  - r )
		//circle centered at origin so: abs( sqrt( x ^ 2 + y ^ 2 ) - r )
		float distanceFromZone = abs( d - zRadius );
		float scaledDistance = distanceFromZone / ( maxRadius );
		//quadratic decrease in color strength
		// y = 1 - x^2
		float scaling = ( 1.0 - ( scaledDistance * scaledDistance ) * 1.0 );
		scaling = clamp( scaling, 0.0, 1.0 );
		color = color.xyz + ( scaling * colors[i].xyz );

		di += 1.0;
	}

	//normalize color
	float m = max( color.x, max( color.y, color.z ) );
	if ( m >= 1.0 )
	{
		color = color.xyz / m;
	}

	return color;
}

void main()
{
	vec2 coordinates = gl_FragCoord.xy - resolution.xy * 0.5;

	vec3 color = preFractalColor( coordinates );
	float fractalVal = distanceEstimate( coordinates );
	color = color.xyz * fractalVal;
	//alpha setting 1
	//float alph = 1.0;
	//alpha setting 2
	//float alph = fractalVal * 2.0;
	//alpha setting 3
	//float alph = fractalVal * 2.0;
	//alph = alph * alph;
	//alpha setting 4
	//float alph = fractalVal * fractalVal;
	//alph = alph * 2.0;
	//alpha setting 5
	float alph = fractalVal * 2.0;
	alph = alph * alph;
	alph = alph * 2.0;

	gl_FragColor = vec4( color, alph );
}