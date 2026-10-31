/// El texto que la app propone leer para clonar una voz (F47, paso 4): uno o
/// dos minutos en voz alta, con preguntas, exclamaciones, números y sonidos
/// variados, para que la muestra tenga de todo lo que la voz va a decir.
///
/// Escritos para la app —no son de nadie—. En los idiomas sin texto propio,
/// `null`: la pantalla pide leer cualquier texto en ese idioma.
String? recordingScript(String language) => _scripts[language];

const _scripts = {
  'es': '''
Hoy quiero contarte cómo empieza una buena mañana. Me despierto temprano, abro la ventana y escucho el ruido de la calle: un colectivo que frena, un perro que ladra, alguien que silba una canción vieja. Pongo el agua para el mate y, mientras se calienta, repaso lo que tengo que hacer.

¿Tengo que leer tres capítulos? ¿Responder doce correos? ¿O preparar la clase del jueves? Primero lo importante: anoto todo en un cuaderno, con letra clara, y tacho lo que ya terminé. ¡Qué alivio da tachar una tarea!

Después salgo a caminar. Me gusta ir por el parque, donde los árboles son altos y el pasto está húmedo. A veces cruzo a mi vecina, que me saluda siempre igual: «¡Buen día! ¿Cómo andás?». Le digo que bien, que con ganas, y seguimos cada uno por su lado.

A las nueve y media vuelvo a casa. Me siento frente a la computadora, respiro hondo y empiezo. Leo despacio, subrayo las ideas que me parecen claves y escribo preguntas en el margen. Cuando algo no se entiende, lo leo en voz alta: escuchar las palabras ayuda a ordenarlas.

Al mediodía hago una pausa. Como algo liviano, miro por la ventana y pienso en lo que aprendí. No siempre es mucho, pero casi siempre es algo. Y eso, al final del día, es lo que más vale.''',
  'en': '''
Today I want to tell you how a good morning begins. I wake up early, open the window and listen to the street: a bus braking, a dog barking, someone whistling an old song. I put the kettle on and, while the water heats up, I go over what I need to do.

Do I have to read three chapters? Answer twelve emails? Or prepare Thursday's class? The important things first: I write everything down in a notebook, in clear handwriting, and cross out what I have already finished. What a relief it is to cross out a task!

Then I go out for a walk. I like going through the park, where the trees are tall and the grass is still wet. Sometimes I run into my neighbour, who always greets me the same way: "Good morning! How are you doing?" I tell her I'm fine, ready for the day, and we each go our own way.

At half past nine I come back home. I sit down at the computer, take a deep breath and start. I read slowly, underline the ideas that seem important and write questions in the margin. When something doesn't make sense, I read it aloud: hearing the words helps to put them in order.

At noon I take a break. I eat something light, look out of the window and think about what I learned. It isn't always a lot, but it's almost always something. And that, at the end of the day, is what matters most.''',
};
