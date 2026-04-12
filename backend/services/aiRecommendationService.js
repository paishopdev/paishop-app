const OpenAI = require("openai");
const { searchGoogleShopping } = require("./googleShoppingService");

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

async function getRecommendations(userQuery) {
  const products = await searchGoogleShopping(userQuery);

  if (!products.length) return [];

  const prompt = `
Sen bir AI alışveriş asistanısın.

Kullanıcı şu ürünü arıyor:
"${userQuery}"

Aşağıdaki ürün listesini analiz et ve en iyi 5 ürünü seç.

Ürünler:
${JSON.stringify(products)}

Her ürün için kısa bir açıklama yaz.

Sadece JSON formatında cevap ver:

[
  {
    "name": "...",
    "price": "...",
    "platform": "...",
    "image": "...",
    "link": "...",
    "rating": 4.5,
    "reviews": 120,
    "short_reason": "neden iyi olduğunu kısa açıkla"
  }
]
`;

  const response = await client.chat.completions.create({
    model: "gpt-4.1-mini",
    messages: [
      {
        role: "user",
        content: prompt,
      },
    ],
  });

  const text = response.choices[0].message.content;

  return JSON.parse(text);
}

module.exports = { getRecommendations };