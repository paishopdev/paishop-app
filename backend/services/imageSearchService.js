const OpenAI = require('openai');

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

function safeParseJson(text) {
  try {
    const cleaned = String(text)
      .replace(/```json/g, '')
      .replace(/```/g, '')
      .trim();

    return JSON.parse(cleaned);
  } catch (e) {
    console.error('IMAGE SEARCH JSON PARSE ERROR:', e.message);
    console.error('RAW IMAGE SEARCH RESPONSE:', text);
    return null;
  }
}

async function generateSearchQueriesFromImages(images = [], userMessage = '') {
  const content = [
    {
      type: 'text',
      text: `
Kullanıcı bir veya daha fazla ürün görseli yükledi ve şu isteği yazdı:
"${userMessage}"

Görevin:
Görsellerdeki ürünü alışveriş aramasına uygun şekilde tanımla.

Öncelik sırası:
1. Marka görünüyorsa önce marka
2. Model / seri görünüyorsa ikinci sırada model
3. Sonra ürün tipi
4. En son gerekirse renk / varyant

Kurallar:
- Sadece geçerli JSON döndür
- Marka net değilse uydurma
- Model net değilse uydurma
- Çok genel kalma
- Aynı ürün için birkaç alternatif arama sorgusu üret
- "spor ayakkabı" gibi aşırı genel ifadelerden kaçın
- Eğer logo / yazı / model seçiliyorsa bunu kullan

JSON formatı:
{
  "primary_query": "en iyi ana arama sorgusu",
  "alternative_queries": [
    "alternatif sorgu 1",
    "alternatif sorgu 2",
    "alternatif sorgu 3"
  ]
}

İyi örnekler:
{
  "primary_query": "Nike Air Force 1 beyaz sneaker",
  "alternative_queries": [
    "Nike beyaz sneaker",
    "Nike Air Force beyaz ayakkabı",
    "beyaz Nike spor ayakkabı"
  ]
}

{
  "primary_query": "JBL Tune 520BT kulaklık",
  "alternative_queries": [
    "JBL bluetooth kulaklık",
    "JBL Tune kulaklık",
    "JBL siyah kulaklık"
  ]
}
      `.trim(),
    },
  ];

  for (const image of images.slice(0, 3)) {
    content.push({
      type: 'image_url',
      image_url: {
        url: `data:${image.mimeType};base64,${image.base64}`,
      },
    });
  }

  const response = await client.chat.completions.create({
    model: 'gpt-4.1-mini',
    messages: [
      {
        role: 'user',
        content,
      },
    ],
    temperature: 0.2,
  });

  const text = response.choices?.[0]?.message?.content?.trim() || '';
  const parsed = safeParseJson(text);

  if (!parsed) {
    return {
      primary_query: '',
      alternative_queries: [],
    };
  }

  return {
    primary_query: String(parsed.primary_query || '').trim(),
    alternative_queries: Array.isArray(parsed.alternative_queries)
        ? parsed.alternative_queries.map((e) => String(e).trim()).filter(Boolean).slice(0, 3)
        : [],
  };
}

async function generateSearchQueryFromImage(base64Image, mimeType = 'image/jpeg') {
  const result = await generateSearchQueriesFromImages(
    [{ mimeType, base64: base64Image }],
    'ürünü bul'
  );

  return result.primary_query || result.alternative_queries[0] || '';
}

module.exports = {
  generateSearchQueryFromImage,
  generateSearchQueriesFromImages,
};